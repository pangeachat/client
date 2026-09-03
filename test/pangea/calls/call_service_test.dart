import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/routes/chat/calls/call_notification.dart';
import 'package:fluffychat/routes/chat/calls/call_service.dart';
import 'package:fluffychat/routes/chat/calls/call_timeouts.dart';
import 'package:fluffychat/routes/chat/calls/call_token_repo.dart';
import 'package:fluffychat/routes/chat/calls/rtc_focus.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Covers what CallService decides before any network or SDK object is involved:
/// whether calling is offered at all, and that constructing the service does not
/// itself start the SDK's VoIP machinery.
void main() {
  // Needed the moment a test builds the SDK's VoIP: its delegate reaches for
  // flutter_webrtc's media devices, which goes through a platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

  Future<Client> bareClient() async => Client(
    'call-service-test',
    // The app's real client registers call membership as important state
    // (client_manager.dart), which is what keeps it in memory for rooms the
    // user has not opened. The reads under test assume exactly that.
    importantStateEvents: {EventTypes.GroupCallMember},
    httpClient: FakeMatrixApi(),
    database: await MatrixSdkDatabase.init(
      'call-service-test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );

  /// Serves `.well-known` and nothing else, so a test can tell a real lookup
  /// from a no-op. Reading a field the SDK only fills in `checkHomeserver` —
  /// which this app never calls — looked correct and discovered nothing.
  http.Client wellKnownServing(Map<String, dynamic> body) =>
      MockClient((request) async {
        if (request.url.path == '/.well-known/matrix/client') {
          return http.Response(
            jsonEncode({
              'm.homeserver': {'base_url': 'http://localhost:8008'},
              ...body,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"errcode":"M_NOT_FOUND"}', 404);
      });

  group('CallService focus discovery', () {
    test('finds the focus its homeserver advertises', () async {
      final client = await bareClient();
      client.homeserver = Uri.parse('http://localhost:8008');

      final service = CallService(
        client,
        focusDiscovery: RtcFocusDiscovery(
          httpClient: wellKnownServing({
            'org.matrix.msc4143.rtc_foci': [
              {'type': 'livekit', 'livekit_service_url': 'http://sfu:7980'},
            ],
          }),
        ),
      );
      final focus = await service.resolveFocus();

      expect(focus, isNotNull);
      expect(focus!.serviceUrl, 'http://sfu:7980');
      expect(service.focus, same(focus), reason: 'and it is remembered');
    });

    test(
      'asks the homeserver we are connected to, not the server name',
      () async {
        // The SDK's own getWellknown resolves against the server name — the
        // delegation point used to FIND a homeserver. This app is configured with
        // one and never discovers it that way, so asking the server name would
        // query a host we are not talking to.
        final asked = <Uri>[];
        final client = await bareClient();
        client.homeserver = Uri.parse('http://localhost:8008');

        await CallService(
          client,
          focusDiscovery: RtcFocusDiscovery(
            httpClient: MockClient((request) async {
              asked.add(request.url);
              return http.Response('{}', 200);
            }),
          ),
        ).resolveFocus();

        expect(asked, [
          Uri.parse('http://localhost:8008/.well-known/matrix/client'),
        ]);
      },
    );

    test(
      'a homeserver that answers 404 is remembered as having none',
      () async {
        var requests = 0;
        final client = await bareClient();
        client.homeserver = Uri.parse('http://localhost:8008');
        final service = CallService(
          client,
          focusDiscovery: RtcFocusDiscovery(
            httpClient: MockClient((_) async {
              requests++;
              return http.Response('{"errcode":"M_NOT_FOUND"}', 404);
            }),
          ),
        );

        expect(await service.resolveFocus(), isNull);
        expect(await service.resolveFocus(), isNull);
        expect(requests, 1, reason: 'a deployment without MatrixRTC is a fact');
      },
    );

    test('a lookup that fails is asked again rather than remembered', () async {
      // One bad moment must not hide the call button for the rest of the
      // session. Only a definitive answer is worth caching.
      var requests = 0;
      final client = await bareClient();
      client.homeserver = Uri.parse('http://localhost:8008');
      final service = CallService(
        client,
        focusDiscovery: RtcFocusDiscovery(
          httpClient: MockClient((_) async {
            requests++;
            if (requests == 1) throw const SocketException('offline');
            return http.Response(
              jsonEncode({
                'org.matrix.msc4143.rtc_foci': [
                  {'type': 'livekit', 'livekit_service_url': 'http://sfu:7980'},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      expect(await service.resolveFocus(), isNull, reason: 'the blip');
      // Past the pause that keeps a retry from becoming a flood.
      await Future.delayed(const Duration(milliseconds: 1));
      service.retryFocusNow();
      final focus = await service.resolveFocus();
      expect(focus, isNotNull, reason: 'and it asked again');
      expect(focus!.serviceUrl, 'http://sfu:7980');
    });

    test('a failed lookup is not re-asked on every room opened', () async {
      // The chat header asks per direct room. Without a pause, an outage would
      // mean one .well-known request for every room the learner opens.
      var requests = 0;
      final client = await bareClient();
      client.homeserver = Uri.parse('http://localhost:8008');
      final service = CallService(
        client,
        focusDiscovery: RtcFocusDiscovery(
          httpClient: MockClient((_) async {
            requests++;
            throw const SocketException('offline');
          }),
        ),
      );

      await service.resolveFocus();
      await service.resolveFocus();
      await service.resolveFocus();
      expect(requests, 1, reason: 'the failure is held briefly');
    });

    test('disposal cancels a held retry', () async {
      // An untracked timer fires into a service whose account has already
      // logged out.
      final client = await bareClient();
      client.homeserver = Uri.parse('http://localhost:8008');
      final service = CallService(
        client,
        focusDiscovery: RtcFocusDiscovery(
          httpClient: MockClient((_) async {
            throw const SocketException('offline');
          }),
        ),
      );

      await service.resolveFocus();
      await expectLater(service.dispose(), completes);
    });

    test('a non-200 that is not 404 is treated as unknown', () async {
      var requests = 0;
      final client = await bareClient();
      client.homeserver = Uri.parse('http://localhost:8008');
      final service = CallService(
        client,
        focusDiscovery: RtcFocusDiscovery(
          httpClient: MockClient((_) async {
            requests++;
            return http.Response('gateway timeout', 504);
          }),
        ),
      );

      expect(await service.resolveFocus(), isNull);
      // Held briefly like any failure, but never treated as an answer: asked
      // again once the pause is dropped.
      service.retryFocusNow();
      expect(await service.resolveFocus(), isNull);
      expect(requests, 2, reason: 'a 504 is not an answer about MatrixRTC');
    });
  });

  group('a join that never comes back', () {
    test('gives the account its calling back', () async {
      // Focus discovery that answers nothing: the network is up but the request
      // hangs, which is what a bad connection looks like from here.
      final client = await bareClient();
      client.homeserver = Uri.parse('http://localhost:8008');
      final service = CallService(
        client,
        joinWithin: const Duration(milliseconds: 50),
        focusDiscovery: RtcFocusDiscovery(
          httpClient: MockClient((_) => Completer<http.Response>().future),
        ),
      );

      await expectLater(
        service.join(Room(id: '!r:server', client: client)),
        throwsA(isA<TimeoutException>()),
      );

      // The claim on this account's one call has to come back. Held, it
      // suppressed every incoming ring and refused every new call — and nothing
      // could release it, because hanging up cannot give back a call that never
      // arrived.
      expect(
        service.isBusy,
        isFalse,
        reason: 'a join that hung must not cost the account its calling',
      );
    });
  });

  group('a join refused because one is already running', () {
    test('does not cancel the join that is actually running', () async {
      // The refused call never held the account's claim. Giving it up on the
      // way out cancelled the join that DOES hold it — somebody else's call,
      // still coming up — and that call then lost its session.
      final client = await bareClient();
      client.homeserver = Uri.parse('http://localhost:8008');
      final held = Completer<http.Response>();
      final service = CallService(
        client,
        focusDiscovery: RtcFocusDiscovery(
          httpClient: MockClient((_) => held.future),
        ),
      );

      final room = Room(id: '!r:server', client: client);
      final first = service.join(room);
      final claimed = service.joinAttempt;
      await expectLater(service.join(room), throwsA(isA<AlreadyInACall>()));

      // What the refused call would do on its way out, with the attempt number
      // it would have had.
      service.abandonJoin(claimed + 1);
      expect(
        service.isBusy,
        isTrue,
        reason: 'the running join still holds the account',
      );

      // And the one that really owns it can still give it up.
      service.abandonJoin(claimed);
      expect(service.isBusy, isFalse);

      held.complete(http.Response('{"errcode":"M_NOT_FOUND"}', 404));
      await expectLater(first, throwsA(isA<Object>()));
    });
  });

  group('two calls that share a membership', () {
    test('do not ring with the same transaction id', () async {
      // A retract that failed leaves the membership in place, and the next call
      // in that room reuses it. Ringing with the same transaction id makes the
      // server hand back the FIRST call's ring — and a decline of that one,
      // long since sent, then marks the new call as turned down.
      final client = await bareClient();
      final service = CallService(client);
      final room = Room(id: '!r:server', client: client);
      final sent = <String>[];

      for (var i = 0; i < 2; i++) {
        try {
          await service.ring(
            room,
            membershipEventId: '\$membership',
            video: false,
          );
        } catch (_) {
          // The send itself cannot succeed against a fake server; the
          // transaction id is what this is about.
        }
        sent.add(service.debugLastRingTxidForTest ?? '');
      }

      expect(sent.first, isNotEmpty);
      expect(sent.first, isNot(sent.last));
    });
  });

  group('a leave that was given up on but is still running', () {
    test('is bounded, but kept until it finishes — never dropped early', () async {
      // The session is fetched by ROOM, so a redial lands on the very object the
      // old leave still holds. Answering after that, it would retract the
      // membership the NEW call had just published — the peer would watch us
      // walk out of a call we had only just joined. So a leave that has not
      // finished is still waited for by the next call; dropping it on the first
      // timeout is what would let that redial race it.
      final service = CallService(
        await bareClient(),
        leaveWithin: const Duration(milliseconds: 50),
      );
      final never = Completer<void>();
      service.setPendingLeaveForTest(never.future);

      // Bounded: a leave that has not answered must not hold up a call the
      // learner is asking for now.
      await service.settlePendingLeave().timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('waiting for a stale leave must be bounded'),
      );

      // Still there after the bounded wait gave up: the next call waits too.
      expect(
        service.hasPendingLeaveForTest,
        isTrue,
        reason: 'a leave still running must keep being waited for',
      );

      // Only its OWN completion lets it go, so no later call waits for nothing.
      never.complete();
      await pumpEventQueue();
      expect(service.hasPendingLeaveForTest, isFalse);
    });

    test('really is waited for, not merely noted', () async {
      final service = CallService(
        await bareClient(),
        leaveWithin: const Duration(seconds: 30),
      );
      var left = false;
      service.setPendingLeaveForTest(
        Future<void>.delayed(
          const Duration(milliseconds: 100),
        ).then((_) => left = true),
      );

      await service.settlePendingLeave();

      expect(
        left,
        isTrue,
        reason: 'the new call must not be built over a leave still running',
      );
    });

    test('a newer leave does not UNRECORD an older one', () async {
      // Two can be outstanding at once by the ordinary route: retract gives up
      // waiting on its leave without stopping it, the redial that follows is
      // abandoned mid-join, and the leave that abandonment issues for the
      // session it was holding is a second one. Recorded in a single slot, the
      // second replaces the first -- and when the second finishes it clears the
      // slot, so the first is left in flight with nothing waiting for it. The
      // call after that then sees nothing to wait for, publishes its membership
      // into the session both leaves hold, and the first lands late and
      // retracts a LIVE call's membership.
      final service = CallService(
        await bareClient(),
        leaveWithin: const Duration(milliseconds: 50),
      );
      final older = Completer<void>();
      final newer = Completer<void>();
      service.setPendingLeaveForTest(older.future);
      service.setPendingLeaveForTest(newer.future);
      expect(
        service.pendingLeaveCountForTest,
        2,
        reason: 'both leaves are in flight, so both are outstanding',
      );

      // The NEWER one finishes first, which is the ordering that hides the bug:
      // it is the one that gets to say the room is clear.
      newer.complete();
      await pumpEventQueue();

      expect(
        service.pendingLeaveCountForTest,
        1,
        reason:
            'the older leave is still running and still has to be waited for',
      );

      // And, as before, it is let go of only by its OWN completion.
      older.complete();
      await pumpEventQueue();
      expect(service.hasPendingLeaveForTest, isFalse);
    });

    test(
      'and the next call waits for the OLDER one, not just the last',
      () async {
        // The count above is bookkeeping; this is the thing the bookkeeping is
        // for. A leave dropped from the tracker is exactly as invisible as one
        // that was never recorded at all, and invisible is what lets a redial
        // publish its membership straight into the session that leave holds.
        final service = CallService(
          await bareClient(),
          leaveWithin: const Duration(seconds: 30),
        );
        var olderFinished = false;
        service.setPendingLeaveForTest(
          Future<void>.delayed(
            const Duration(milliseconds: 100),
          ).then((_) => olderFinished = true),
        );
        final newer = Completer<void>();
        service.setPendingLeaveForTest(newer.future);
        newer.complete();
        await pumpEventQueue();

        expect(
          olderFinished,
          isFalse,
          reason:
              'the older leave must still be running for this to prove '
              'anything -- if it has already finished, the wait below is vacuous',
        );

        await service.settlePendingLeave();

        expect(
          olderFinished,
          isTrue,
          reason: 'the new call must not be built over a leave still running',
        );
      },
    );

    test('is recorded by the hangup that issued it, too', () async {
      // The other site the funnel covers. A retract that gives up waiting has
      // NOT stopped its leave, and the session is fetched by room -- so unless
      // that leave is recorded here as well, the next call in this room races
      // the very thing that is about to retract it. This site happened to get
      // it right while the abandoned-join site did not; what makes that stay
      // true is that there is now one way to leave, not two to keep in step.
      final client = await bareClient();
      final calls = CallService(
        client,
        leaveWithin: const Duration(milliseconds: 50),
      );
      final session = _LeavingSession(
        client: client,
        room: Room(id: '!r:fakeServer.notExisting', client: client),
        voip: calls.voip,
        backend: LiveKitBackend(
          livekitServiceUrl: 'http://sfu:7980',
          livekitAlias: 'alias',
          e2eeEnabled: false,
        ),
        groupCallId: 'call-id',
        application: 'm.call',
        scope: 'm.room',
      )..leaveGate = Completer<void>();
      calls.adoptSessionForTest(session);

      // Given up on after the bounded wait: the membership will expire by
      // itself, and the learner is not locked out of calling meanwhile.
      await expectLater(calls.retract(), completion(isFalse));

      expect(session.leaves, 1);
      expect(
        calls.hasPendingLeaveForTest,
        isTrue,
        reason: 'the leave is still running, so the next call must wait for it',
      );
    });
  });

  group('a retract that answered without ever leaving', () {
    test('does not latch every later retract onto its answer', () async {
      // The in-flight latch is what makes concurrent hangups join one attempt.
      // It is assigned by `_retracting ??= ...`, and the body it memoizes has a
      // path that returns without ever awaiting -- there is no call to retract.
      // An async body runs synchronously until its first await, so on that path
      // the whole body, its `finally` included, finishes BEFORE the assignment
      // lands: the clear runs first and the latch is set afterwards, with
      // nothing left to clear it.
      //
      // Every later retract then returns that finished future -- true,
      // immediately, having left nothing -- so the membership stays advertised
      // and the session is never released. `isBusy` reads that session for
      // ever: every new call refused, every incoming ring declined as busy.
      final client = await bareClient();
      final calls = CallService(
        client,
        leaveWithin: const Duration(milliseconds: 50),
      );

      // The path with nothing to retract: a hangup on a call that never came
      // up, which is ordinary traffic rather than a corner.
      await expectLater(
        calls.retract(),
        completion(isTrue),
        reason: 'nothing was advertised, so nothing was left advertised',
      );

      // A real call now, and the hangup that has to take its membership back.
      final session = _LeavingSession(
        client: client,
        room: Room(id: '!r:fakeServer.notExisting', client: client),
        voip: calls.voip,
        backend: LiveKitBackend(
          livekitServiceUrl: 'http://sfu:7980',
          livekitAlias: 'alias',
          e2eeEnabled: false,
        ),
        groupCallId: 'call-id',
        application: 'm.call',
        scope: 'm.room',
      );
      calls.adoptSessionForTest(session);

      await expectLater(calls.retract(), completion(isTrue));

      expect(
        session.leaves,
        1,
        reason: 'the second retract had a membership to take back and took it',
      );
      expect(
        calls.hasJoinedSession,
        isFalse,
        reason: 'a session never released goes on refusing every later call',
      );
      expect(calls.isBusy, isFalse);
    });
  });

  group('a retract that is running but holds no leave right now', () {
    // `_leaving` holds a leave only while its future is outstanding, and its
    // whenComplete removes one that FAILED just as readily as one that worked.
    // A retract in flight is therefore not always holding a leave: between its
    // retries it sleeps for a second, then two, with the failed one already
    // forgotten -- and it is going to issue another. In that window join, whose
    // only serialisation is settlePendingLeave, and announce, whose
    // announceStillHolds re-check is nested INSIDE `if (pendingLeave != null)`,
    // both see nothing to wait for and run straight over it.
    //
    // The same lesson as announceStillHolds, one step further along: what a
    // redial has to be ordered behind is every leave this service is STILL
    // GOING TO ISSUE, not merely the ones already on the wire.
    const me = '@test:fakeServer.notExisting';
    var roomSeq = 0;

    /// A logged-in client whose room already carries OUR standing membership
    /// for the call the session names.
    ///
    /// Required, and not scenery: the retract's catch asks whether the
    /// membership is still there, and a leave that threw with nothing left in
    /// state is treated as a write that landed -- which returns at once instead
    /// of retrying. The retry loop, and the sleep inside it, exist only for a
    /// leave that failed with the membership still standing.
    Future<(_JoinSteps, Room, Room)> joinedWithStandingMembership() async {
      final roomId = '!redial${roomSeq++}:fakeServer.notExisting';
      final elsewhereId = '!elsewhere${roomSeq++}:fakeServer.notExisting';
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(user: me),
        deviceId: 'GHTYAJCE',
      );
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.GroupCallMember,
                    content: {
                      'memberships': [
                        {
                          'call_id': 'call-id',
                          'application': 'm.call',
                          'scope': 'm.room',
                          'foci_active': [
                            {
                              'type': 'livekit',
                              'livekit_alias': 'alias',
                              'livekit_service_url': 'http://sfu:7980',
                            },
                          ],
                          'device_id': 'GHTYAJCE',
                          'expires_ts': DateTime.now()
                              .add(const Duration(minutes: 10))
                              .millisecondsSinceEpoch,
                          'membershipID': 'ours',
                        },
                      ],
                    },
                    senderId: me,
                    eventId: '\$ours',
                    originServerTs: DateTime.now(),
                    stateKey: me,
                  ),
                ],
              ),
              elsewhereId: JoinedRoomUpdate(state: const []),
            },
          ),
        ),
      );
      final calls = _JoinSteps(
        client,
        focusDiscovery: _FixedFocus(),
        leaveWithin: const Duration(milliseconds: 50),
      );
      return (
        calls,
        client.getRoomById(roomId)!,
        client.getRoomById(elsewhereId)!,
      );
    }

    /// Drives a service to the window: a retract asleep between its retries,
    /// with nothing outstanding in `_leaving` to show for it.
    Future<(_JoinSteps, Room, Room, _LeavingSession, Future<bool>)>
    retractSleepingBetweenRetries() async {
      final (calls, room, elsewhere) = await joinedWithStandingMembership();
      await calls.join(room);
      final session = calls.session!;

      // The first hangup gives up: its leave never answers, so the membership
      // is left to expire and the session is KEPT for a later retry. That is
      // what lets the redial below past join's guard at all -- an abandoned
      // membership is discarded there rather than refusing the new call.
      session.leaveGate = Completer<void>();
      await expectLater(calls.retract(), completion(isFalse));
      // And that leave has since finished, so nothing is outstanding. Without
      // this the test would be exercising the window that IS covered.
      session.leaveGate!.complete();
      await pumpEventQueue();
      expect(calls.hasPendingLeaveForTest, isFalse);

      // The retry the design intends. Its first attempt fails with the
      // membership still standing, which is what sends it round the loop.
      session.leaveGate = null;
      session.leaveThrowsInOrder.add(StateError('the server refused'));
      final retracting = calls.retract();
      await pumpEventQueue();

      expect(
        session.leaves,
        2,
        reason: 'the retry has issued its leave and had it refused',
      );
      expect(
        calls.hasPendingLeaveForTest,
        isFalse,
        reason:
            'the failed leave is forgotten, so this really is the window: a '
            'retract in flight with nothing in _leaving to see it by',
      );
      return (calls, room, elsewhere, session, retracting);
    }

    test(
      'a redial does not publish into the session it is about to leave',
      () async {
        final (calls, room, _, session, retracting) =
            await retractSleepingBetweenRetries();

        // The redial, inside the sleep. The session is fetched BY ROOM, so this
        // is handed the very object the sleeping retract is holding.
        await calls.join(room);
        expect(calls.hasJoinedSession, isTrue);

        final published = await calls.announce();

        expect(
          session.enters,
          0,
          reason:
              'a membership published here is one the retract takes straight '
              'back: the peer watches us join and immediately walk out',
        );
        expect(
          published,
          isNull,
          reason:
              'and the call is told it has no membership, rather than lied to',
        );

        await expectLater(retracting, completion(isTrue));
      },
    );

    test('and it does not call a live call abandoned on its way out', () async {
      // The third way the same sleeping retract can reach past its own call.
      // `_abandonedMembership` is service-wide, so a retract that GIVES UP
      // after a redial has landed says "abandoned" about the call now in hand.
      // The cost is not cosmetic: `isBusy` is computed from that flag, so a
      // live call reads as not-busy and a second incoming call can interrupt
      // it, and the next join discards it as unretractable.
      final (calls, _, elsewhere, session, retracting) =
          await retractSleepingBetweenRetries();

      // Every remaining attempt fails, so this retract gives up rather than
      // succeeding -- that is the path that writes the flag.
      session.leaveThrowsInOrder.addAll([
        StateError('still refused'),
        StateError('and again'),
        StateError('and again'),
      ]);

      await calls.join(elsewhere);
      expect(calls.sessionsByRoom[elsewhere.id], isNotNull);

      await expectLater(retracting, completion(isFalse));

      expect(
        calls.isBusy,
        isTrue,
        reason:
            'the call in the other room is up, so the service must still '
            'refuse a second one',
      );
      expect(
        calls.hasJoinedSession,
        isTrue,
        reason: 'and a later hangup must still have something to retract',
      );
    });

    test('and its finally does not release a call it never held', () async {
      // The other half. retract captured `_current` before it slept, and its
      // finally clears `_current` on the way out without checking that it is
      // still the same session -- so a call placed MEANWHILE, in another room,
      // is dropped by the service: isBusy goes false with the call still up, a
      // second incoming call can interrupt it, and nothing can retract it.
      final (calls, _, elsewhere, _, retracting) =
          await retractSleepingBetweenRetries();

      await calls.join(elsewhere);
      final live = calls.sessionsByRoom[elsewhere.id];
      expect(live, isNotNull, reason: 'a different room, so a different call');

      await expectLater(retracting, completion(isTrue));

      expect(
        calls.hasJoinedSession,
        isTrue,
        reason: 'the call in the other room is still up and still ours to end',
      );
      expect(calls.isBusy, isTrue);
    });
  });

  group('a membership that could not be taken back', () {
    test('does not go on suppressing calls to this account', () {
      // Retracting is given up on when the server will not take it: the
      // membership expires by itself in minutes. Until then the session is kept
      // so a later attempt has something to retry WITH — and that kept session
      // went on reading as a call in progress, so every incoming ring was
      // suppressed and the learner simply stopped receiving calls.
      expect(
        CallService.busyFrom(hasSession: true, abandoned: true, joining: false),
        isFalse,
        reason: 'nothing is live: nothing was able to hold that membership',
      );
      expect(
        CallService.busyFrom(
          hasSession: true,
          abandoned: false,
          joining: false,
        ),
        isTrue,
        reason: 'a call that is genuinely up',
      );
      expect(
        CallService.busyFrom(hasSession: false, abandoned: true, joining: true),
        isTrue,
        reason: 'a join in flight claims the account before the session exists',
      );
      expect(
        CallService.busyFrom(
          hasSession: false,
          abandoned: false,
          joining: false,
        ),
        isFalse,
      );
    });
  });

  group('a join that was given up on', () {
    // The session is fetched by ROOM, so the attempt that was abandoned and the
    // one that is live can be holding the very same object. Handing it back
    // then retracts the call that is actually up — a conversation dropped, to
    // prevent a membership that would have expired by itself.
    test('hands its session back only when nobody else holds it', () {
      expect(
        CallService.releasesAbandonedSession(
          joinInFlight: false,
          isCurrent: false,
        ),
        isTrue,
        reason: 'nothing else wants it, so it must not be left advertised',
      );
      expect(
        CallService.releasesAbandonedSession(
          joinInFlight: false,
          isCurrent: true,
        ),
        isFalse,
        reason: 'this is the call that is up',
      );
      expect(
        CallService.releasesAbandonedSession(
          joinInFlight: true,
          isCurrent: false,
        ),
        isFalse,
        reason: 'a retry is about to claim it, and will clean up if it fails',
      );
      expect(
        CallService.releasesAbandonedSession(
          joinInFlight: true,
          isCurrent: true,
        ),
        isFalse,
      );
    });
  });

  group('a join given up on between its own steps', () {
    // An await is a place a decision can be superseded, and nothing after one
    // may act on the decision that preceded it. The check used to sit BELOW the
    // token request, so a join abandoned while the session was being fetched
    // still spent a choreographer request on itself -- and if that request
    // failed, the throw carried straight past the check and the session was
    // never handed back.
    Future<(_JoinSteps, Room)> service({
      Object? tokenThrows,
      Duration? leaveWithin,
    }) async {
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(
          user: '@test:fakeServer.notExisting',
        ),
        deviceId: 'GHTYAJCE',
      );
      final calls = _JoinSteps(
        client,
        focusDiscovery: _FixedFocus(),
        leaveWithin: leaveWithin,
      )..tokenThrows = tokenThrows;
      return (calls, Room(id: '!r:fakeServer.notExisting', client: client));
    }

    test('never asks for a token on behalf of a call nobody wants', () async {
      final (calls, room) = await service();
      final joining = calls.join(room);
      calls.duringFetch = () => calls.abandonJoin(calls.joinAttempt);

      await expectLater(joining, throwsA(isA<StateError>()));

      expect(calls.steps, [
        'session',
      ], reason: 'the token is a request made for a call that is over');
      expect(
        calls.session?.leaves,
        1,
        reason: 'and the session it did fetch is handed back',
      );
    });

    test('hands its session back even when the token request fails', () async {
      // The regression itself. The release lived below the token await, so a
      // token that threw skipped it entirely -- and the membership stood until
      // it expired minutes later, with nothing left holding a handle to it.
      final (calls, room) = await service(
        tokenThrows: StateError('the token service is down'),
      );
      final joining = calls.join(room);
      calls.duringToken = () => calls.abandonJoin(calls.joinAttempt);

      await expectLater(joining, throwsA(isA<StateError>()));

      expect(calls.steps, ['session', 'token']);
      expect(
        calls.session?.leaves,
        1,
        reason: 'a failed token must not strand the session already fetched',
      );
    });

    test(
      'a token failure on a call still wanted is the caller\'s to hear',
      () async {
        // The other side of the same guard: when nothing superseded the join, the
        // guard must return and let the original failure out rather than
        // replacing it with an abandonment nobody performed.
        final (calls, room) = await service(tokenThrows: const _TokenRefused());

        await expectLater(calls.join(room), throwsA(isA<_TokenRefused>()));

        expect(
          calls.session?.leaves,
          0,
          reason: 'nothing superseded this join, so it hands nothing back',
        );
      },
    );

    test('hands it back as a leave the next call can wait for', () async {
      // The rule: every leave this service issues has to be recorded as the
      // pending one, because the next join's correctness is built out of
      // waiting for it. This leave went straight at the session, so
      // settlePendingLeave found nothing to wait for -- and since the session
      // is fetched by ROOM, the redial was handed the very object this leave
      // was about to retract. It published its membership into that session and
      // then watched the older, dead call's leave take it back.
      final (calls, room) = await service(
        leaveWithin: const Duration(seconds: 30),
      );
      final held = Completer<void>();
      // Released whatever happens, so an assertion that fails partway leaves no
      // future parked on a gate nothing will ever open — otherwise a real
      // regression here reports as a timeout minutes later instead of as the
      // expectation it actually broke.
      addTearDown(() {
        if (!held.isCompleted) held.complete();
      });

      final abandoned = calls.join(room);
      // Registered now rather than where it is awaited at the end: this join
      // throws its abandonment the instant the held leave answers, and a
      // rejection nothing is yet listening for is reported as an unhandled
      // error instead of the expected one.
      final abandonedThrows = expectLater(
        abandoned,
        throwsA(isA<StateError>()),
      );
      // The hangup lands inside the fetch, which is where the abandoned join
      // hands the session back. The leave is held open from the same place, so
      // the window it opens is a real one rather than one already closed.
      calls.duringFetch = () {
        calls.session!.leaveGate = held;
        calls.abandonJoin(calls.joinAttempt);
      };
      await pumpEventQueue();
      calls.duringFetch = null;

      expect(calls.session?.leaves, 1, reason: 'precondition: it did leave');
      expect(
        calls.hasPendingLeaveForTest,
        isTrue,
        reason: 'a leave nothing recorded is invisible to the next join',
      );

      // The redial, while that leave is still in flight. It must park behind it
      // rather than fetch the session out from under it.
      final redial = calls.join(room);
      await pumpEventQueue();
      expect(
        calls.steps,
        ['session'],
        reason: 'the second join must not reach the session mid-leave',
      );

      held.complete();
      await expectLater(redial, completion(isA<CallToken>()));
      expect(calls.steps, [
        'session',
        'session',
        'token',
      ], reason: 'and it goes ahead the moment the leave finishes');
      await abandonedThrows;
    });
  });

  group('an announce parked behind a leave that is still finishing', () {
    // The same rule, on the other side of the join. The session is read before
    // the wait, and the wait is bounded in SECONDS -- long enough for a hangup
    // to run a whole retract inside it. Entering afterwards publishes a
    // membership the service is no longer tracking, and the next retract finds
    // nothing to leave and reports a success it has not achieved: the peer goes
    // on seeing us in a call we left, until the membership expires.
    test('does not enter a call that was retracted while it waited', () async {
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(
          user: '@test:fakeServer.notExisting',
        ),
        deviceId: 'GHTYAJCE',
      );
      final calls = CallService(
        client,
        leaveWithin: const Duration(milliseconds: 50),
      );
      final session = _LeavingSession(
        client: client,
        room: Room(id: '!r:fakeServer.notExisting', client: client),
        voip: calls.voip,
        backend: LiveKitBackend(
          livekitServiceUrl: 'http://sfu:7980',
          livekitAlias: 'alias',
          e2eeEnabled: false,
        ),
        groupCallId: 'call-id',
        application: 'm.call',
        scope: 'm.room',
      );
      calls.adoptSessionForTest(session);
      // A leave from the LAST call that never answers, which is what parks the
      // announce long enough for anything to happen inside it.
      calls.setPendingLeaveForTest(Completer<void>().future);

      final announcing = calls.announce();
      await pumpEventQueue();
      // The user hangs up. This one really does leave and really does release
      // the session, so what the announce resumes into is the true end state.
      await expectLater(calls.retract(), completion(isTrue));

      expect(await announcing, isNull);
      expect(
        session.enters,
        0,
        reason: 'a membership published now is one nothing can take back',
      );
    });

    test('does not enter a call whose own hangup is still leaving it', () async {
      // The same wait, superseded by THIS call rather than by a later one. The
      // snapshot was taken before the hangup, so the announce never sees the
      // leave the hangup issues -- and `_current` still points at the session
      // for the whole time that leave is in flight, because retract clears it
      // only once the leave has finished. Identity therefore says yes to the
      // one session in the world that must not be entered: the enter would land
      // beside a leave for the SAME session, and whichever landed last would
      // decide whether the peer sees a call we left or misses one we joined.
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(
          user: '@test:fakeServer.notExisting',
        ),
        deviceId: 'GHTYAJCE',
      );
      final calls = CallService(client);
      final session = _LeavingSession(
        client: client,
        room: Room(id: '!r:fakeServer.notExisting', client: client),
        voip: calls.voip,
        backend: LiveKitBackend(
          livekitServiceUrl: 'http://sfu:7980',
          livekitAlias: 'alias',
          e2eeEnabled: false,
        ),
        groupCallId: 'call-id',
        application: 'm.call',
        scope: 'm.room',
      );
      // This call's own hangup will not finish on its own, which is what keeps
      // it in flight when the announce wakes up.
      session.leaveGate = Completer<void>();
      calls.adoptSessionForTest(session);
      // The leave from the LAST call, which is what the announce parks on. It
      // is completed by hand below, so the announce wakes on the leave finishing
      // rather than on a timeout -- no clock is being raced here.
      final lastCallsLeave = Completer<void>();
      calls.setPendingLeaveForTest(lastCallsLeave.future);

      final announcing = calls.announce();
      await pumpEventQueue();

      final retracting = calls.retract();
      await pumpEventQueue();
      expect(
        session.leaves,
        1,
        reason: 'the hangup has issued its leave and is waiting on it',
      );

      lastCallsLeave.complete();

      expect(await announcing, isNull);
      expect(
        session.enters,
        0,
        reason: 'an enter here races the leave of the call it belongs to',
      );

      session.leaveGate!.complete();
      await expectLater(retracting, completion(isTrue));
    });
  });

  group('a membership waiting behind a leave', () {
    // The predicate the wait re-establishes itself on. Identity is one of its
    // three terms and the only one an earlier version had.
    test('is still wanted only while nothing is taking it back', () {
      expect(
        CallService.announceStillHolds(
          isCurrent: true,
          retractInFlight: false,
          membershipAbandoned: false,
        ),
        isTrue,
        reason: 'the ordinary case: the call is up and nobody is leaving it',
      );
      expect(
        CallService.announceStillHolds(
          isCurrent: false,
          retractInFlight: false,
          membershipAbandoned: false,
        ),
        isFalse,
        reason: 'a hangup ran to completion inside the wait',
      );
      expect(
        CallService.announceStillHolds(
          isCurrent: true,
          retractInFlight: true,
          membershipAbandoned: false,
        ),
        isFalse,
        reason:
            'the hangup is still leaving this very session, and retract clears '
            'the current call only once its leave has finished',
      );
      expect(
        CallService.announceStillHolds(
          isCurrent: true,
          retractInFlight: false,
          membershipAbandoned: true,
        ),
        isFalse,
        reason:
            'the hangup gave up on the leave, which KEEPS the session so a '
            'retry has something to retry with -- not so it can be entered',
      );
    });
  });

  group('CallService availability', () {
    test('is unavailable when the homeserver advertises no RTC focus', () async {
      // The ordinary state for a homeserver without MatrixRTC configured. Callers
      // use this to hide the call affordance instead of offering a button that
      // cannot work.
      final service = CallService(await bareClient());
      expect(await service.resolveFocus(), isNull);
      expect(service.focus, isNull);
    });

    test('constructing the service does not construct VoIP', () async {
      // VoIP() is not inert: it scans every joined room for existing call
      // memberships, can invoke handleNewGroupCall before returning, and
      // dereferences delegate.mediaDevices inline. An account that never places a
      // call should never pay for that.
      final service = CallService(await bareClient());
      expect(service.voipConstructed, isFalse);
    });

    test(
      'the SDK is given this app\'s delayed-leave timings, not its own',
      () async {
        // The SDK's defaults put a delayed-leave restart on the wire every four
        // seconds per participant, all devices on the same period. The numbers
        // that replace them, and why the two had to move together, are derived in
        // call_timeouts_test.dart; this is the wiring -- without it every one of
        // those numbers is a constant nothing reads.
        final service = CallService(await bareClient());
        final timeouts = service.voip.timeouts!;

        expect(timeouts.delayedEventApplyLeave, CallDelayedLeave.applyLeave);
        expect(
          timeouts.delayedEventRestart,
          greaterThanOrEqualTo(CallDelayedLeave.minRestart),
        );
        expect(
          timeouts.delayedEventRestart,
          lessThanOrEqualTo(CallDelayedLeave.maxRestart),
        );
      },
    );

    test(
      'joining without a focus fails loudly rather than half-starting a call',
      () async {
        // The failure has to arrive before any Matrix state is published: a call
        // announced to the room but unreachable by media is worse than no call.
        final client = await bareClient();
        client.homeserver = Uri.parse('http://localhost:8008');
        final service = CallService(
          client,
          focusDiscovery: RtcFocusDiscovery(
            httpClient: MockClient(
              (_) async => http.Response('{"errcode":"M_NOT_FOUND"}', 404),
            ),
          ),
        );

        await expectLater(
          service.join(Room(id: '!r:server', client: client)),
          throwsStateError,
        );
        expect(
          service.voipConstructed,
          isFalse,
          reason: 'VoIP scans every room and can fire handlers on construction',
        );
        expect(service.hasJoinedSession, isFalse);
      },
    );

    test(
      'a second join is refused while the first is still connecting',
      () async {
        // Checking the current session alone is check-then-act across three
        // round-trips: both callers would pass, both would create a session, and
        // the second would orphan the first's membership.
        final client = await bareClient();
        client.homeserver = Uri.parse('http://localhost:8008');
        final held = Completer<http.Response>();
        final service = CallService(
          client,
          focusDiscovery: RtcFocusDiscovery(
            httpClient: MockClient((_) => held.future),
          ),
        );

        final first = service.join(Room(id: '!r:server', client: client));
        await expectLater(
          service.join(Room(id: '!r:server', client: client)),
          throwsA(isA<AlreadyInACall>()),
          reason:
              'a refusal is told apart from a join that failed, because the '
              'refused one never held the claim and must not give it up',
        );

        held.complete(http.Response('{"errcode":"M_NOT_FOUND"}', 404));
        await expectLater(first, throwsStateError);
      },
    );
  });
  test('a join that lands after logout does not build a call', () async {
    // Discovery is a network round-trip and an account can log out inside it.
    // Resuming would construct a VoIP instance, with listeners on a client
    // being torn down, after teardown had already found nothing to clean up.
    final client = await bareClient();
    client.homeserver = Uri.parse('http://localhost:8008');

    final held = Completer<void>();
    final service = CallService(client, focusDiscovery: _HeldDiscovery(held));

    final joining = service.join(Room(id: '!r:server', client: client));
    await pumpEventQueue();
    final disposing = service.dispose();
    held.complete();
    await disposing;

    await expectLater(joining, throwsA(isA<StateError>()));
    expect(
      service.voipConstructed,
      isFalse,
      reason: 'nothing may be built for an account that has gone',
    );
  });
  group('the ring transaction id', () {
    // A homeserver deduplicates by transaction id: a repeat returns the ORIGINAL
    // event and writes nothing. A repeated ring id therefore means the callee's
    // phone never rings, while the caller sits through the whole lifetime and
    // records a missed call. Measured on a live server before this was fixed,
    // every ring id was being sent exactly twice.
    Future<CallService> service() async {
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(
          user: '@test:fakeServer.notExisting',
        ),
        deviceId: 'GHTYAJCE',
      );
      return CallService(client);
    }

    test(
      'is never reused, even by a fresh service on the same membership',
      () async {
        // A page reload builds a new CallService, so its ring counter starts at
        // one again -- and the membership event id is reused whenever a join
        // finds a membership already standing. Counter plus membership alone
        // therefore rebuilds an id this account has already used.
        final first = await service();
        final second = await service();
        const membership = r'$the-same-membership';

        await first.ring(
          _TxidRoom(id: '!r:fakeServer.notExisting', client: first.client),
          membershipEventId: membership,
          video: false,
        );
        await second.ring(
          _TxidRoom(id: '!r:fakeServer.notExisting', client: second.client),
          membershipEventId: membership,
          video: false,
        );

        expect(
          second.debugLastRingTxidForTest,
          isNot(equals(first.debugLastRingTxidForTest)),
          reason: 'a reused ring id is silently swallowed by the homeserver',
        );
      },
    );

    test('is the same across the retry of one ring', () async {
      // The retry must ask for the SAME event, or a send whose response was
      // merely lost would ring the other side a second time.
      final calls = await service();
      final room = _TxidRoom(
        id: '!r:fakeServer.notExisting',
        client: calls.client,
      );
      await calls.ring(room, membershipEventId: r'$m', video: false);
      expect(room.txids, isNotEmpty);
      expect(room.txids.toSet().length, 1, reason: 'one id for one ring');
    });
  });

  group('a leave that throws after the membership is already gone', () {
    // `GroupCallSession.leave()` writes the emptied membership FIRST and only
    // then does its own teardown. When a later step throws, the peer has
    // already watched us go, but the ended state and the session registry are
    // never reached -- and a session left behind there is what makes the NEXT
    // call in the room fail as though we were still in this one. In production
    // the throw comes from the SDK's delayed-event bookkeeping; the shape that
    // matters, and what is reproduced here, is a throw AFTER the write lands.
    Future<(CallService, GroupCallSession, Room)> joinedService() async {
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(
          user: '@test:fakeServer.notExisting',
        ),
        deviceId: 'GHTYAJCE',
      );
      final service = CallService(client);
      final room = Room(id: '!left:fakeServer.notExisting', client: client);
      final session = GroupCallSession(
        client: client,
        room: room,
        voip: service.voip,
        backend: _ThrowsAfterTheWrite(),
        groupCallId: 'call-id',
        application: 'm.call',
        scope: 'm.room',
      );
      service.adoptSessionForTest(session);
      return (service, session, room);
    }

    test(
      'is reported as the success it is, and releases the session',
      () async {
        final (service, _, room) = await joinedService();
        expect(
          service.membershipEventIdIn(service.joinAttempt),
          isNull,
          reason: 'precondition: nothing of ours is left in the room',
        );

        await expectLater(
          service.retract(),
          completion(isTrue),
          reason:
              'the membership is gone, which is the whole point of a retract',
        );
        expect(
          service.hasJoinedSession,
          isFalse,
          reason: 'a session kept here refuses the next call in this room',
        );
      },
    );

    test('finishes the teardown the aborted leave skipped', () async {
      final (service, session, _) = await joinedService();
      expect(session.state, isNot(GroupCallState.ended));

      await service.retract();

      expect(
        session.state,
        GroupCallState.ended,
        reason: 'leave() throws before it ends the session, so we must',
      );
    });
  });

  group('a ring that landed before the page was reloaded', () {
    // incomingRings is a LIVE stream: a ring already delivered before a reload
    // never comes through it again. Before this, refreshing while the phone was
    // ringing lost the call outright, with no way left to answer it.
    const caller = '@friend:fakeServer.notExisting';
    const roomId = '!ringing:fakeServer.notExisting';

    Future<CallService> synced({
      required bool callerPresent,
      Duration age = Duration.zero,
      bool declinedByMe = false,
    }) async {
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(
          user: '@test:fakeServer.notExisting',
        ),
        deviceId: 'GHTYAJCE',
      );
      final at = DateTime.now().subtract(age);
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.GroupCallMember,
                    content: {
                      'memberships': callerPresent
                          ? [
                              {'call_id': 'call-id', 'device_id': 'CALLERDEV'},
                            ]
                          : <Map<String, dynamic>>[],
                    },
                    senderId: caller,
                    eventId: r'$mem',
                    originServerTs: at,
                    stateKey: caller,
                  ),
                ],
                timeline: TimelineUpdate(
                  events: [
                    MatrixEvent(
                      type: PangeaEventTypes.callNotification,
                      content: const CallNotification(
                        membershipEventId: r'$mem',
                        senderDeviceId: 'CALLERDEV',
                        video: false,
                      ).toContent(at),
                      senderId: caller,
                      eventId: r'$ring',
                      originServerTs: at,
                    ),
                    if (declinedByMe)
                      MatrixEvent(
                        type: PangeaEventTypes.callDecline,
                        content: const {
                          'm.relates_to': {
                            'rel_type': 'm.reference',
                            'event_id': r'$ring',
                          },
                        },
                        senderId: '@test:fakeServer.notExisting',
                        eventId: r'$decline',
                        originServerTs: at,
                      ),
                  ],
                ),
              ),
            },
          ),
        ),
      );
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          caller: [roomId],
        },
      );
      return CallService(client);
    }

    test('is found again so the call can still be answered', () async {
      final service = await synced(callerPresent: true);
      final missed = await service.ringsMissed();
      expect(missed.map((r) => r.event.eventId), [r'$ring']);
    });

    test('is not found when the caller has already gone', () async {
      // A ring whose caller has left is a call that is already over; replaying
      // it would offer to answer nobody.
      final service = await synced(callerPresent: false);
      expect(await service.ringsMissed(), isEmpty);
    });

    test('is not found once its lifetime has run out', () async {
      // Inside the scan window (90s) but past the ring's own 30s lifetime, so
      // this exercises the ring's expiry rather than the coarse timeline cutoff.
      final service = await synced(
        callerPresent: true,
        age: const Duration(seconds: 60),
      );
      expect(await service.ringsMissed(), isEmpty);
    });

    test('is not found when this account already turned it down', () async {
      // Declining then reloading must not put the prompt back up.
      final service = await synced(callerPresent: true, declinedByMe: true);
      expect(await service.ringsMissed(), isEmpty);
    });
  });
  group('offering a return to a call after a reload', () {
    const roomId = '!wascalling:fakeServer.notExisting';

    setUp(() => SharedPreferences.setMockInitialValues({}));
    const peer = '@friend:fakeServer.notExisting';
    const me = '@test:fakeServer.notExisting';

    Future<Client> clientWithOwnMembership({
      required bool live,
      String deviceId = 'GHTYAJCE',
    }) async {
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(user: me),
        deviceId: 'GHTYAJCE',
      );
      final expires = DateTime.now()
          .add(live ? const Duration(minutes: 5) : const Duration(minutes: -30))
          .millisecondsSinceEpoch;
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.GroupCallMember,
                    content: {
                      'memberships': [
                        {
                          'call_id': 'call-id',
                          'device_id': deviceId,
                          'expires_ts': expires,
                        },
                      ],
                    },
                    senderId: me,
                    eventId: r'$own-membership',
                    originServerTs: DateTime.now(),
                    stateKey: '${deviceId}_$me',
                  ),
                ],
              ),
            },
          ),
        ),
      );
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          peer: [roomId],
        },
      );
      return client;
    }

    test('the breadcrumb outranks the membership scan', () async {
      // On a delayed-events server the membership can be retracted seconds
      // after the reload -- racing this very scan. The call's own local
      // trace answers to nothing but its age.
      SharedPreferences.setMockInitialValues({
        'pangea.call.breadcrumb.call-service-test':
            '{"roomId":"$roomId","membershipEventId":"\$from-crumb",'
            '"at":${DateTime.now().millisecondsSinceEpoch}}',
      });
      final service = CallService(await clientWithOwnMembership(live: false));
      final offers = await service.rejoinOffers();
      expect(offers, hasLength(1));
      expect(offers.single.membershipEventId, r'$from-crumb');
      // The crumb's written-at rides along: it is the arbitration line that
      // tells the call's own replayed ring from a genuine redial. A crumb
      // offer without it silently loses that distinction.
      expect(offers.single.since, isNotNull);
    });

    test('a crumb for an unknown room falls back to the scan', () async {
      SharedPreferences.setMockInitialValues({
        'pangea.call.breadcrumb.call-service-test':
            '{"roomId":"!gone:server","membershipEventId":"\$x",'
            '"at":${DateTime.now().millisecondsSinceEpoch}}',
      });
      final service = CallService(await clientWithOwnMembership(live: true));
      final offers = await service.rejoinOffers();
      expect(offers, hasLength(1));
      expect(offers.single.membershipEventId, r'$own-membership');
    });

    test('a live membership of this device is offered back', () async {
      final service = CallService(await clientWithOwnMembership(live: true));
      final offers = await service.rejoinOffers();
      expect(offers, hasLength(1));
      expect(offers.single.room.id, roomId);
      // The offer carries the call's standing identity: the membership event
      // this account wrote when it first joined, which the rejoined session
      // uses as its anchor instead of minting a new one.
      expect(offers.single.membershipEventId, r'$own-membership');
      expect(
        service.voipConstructed,
        isFalse,
        reason:
            'the scan runs at every app start; VoIP() scans every room and '
            'can fire call handlers on construction, and an account that was '
            'not in a call must never pay that',
      );
    });

    test('an expired membership offers nothing', () async {
      final service = CallService(await clientWithOwnMembership(live: false));
      expect(await service.rejoinOffers(), isEmpty);
    });

    test("another device's membership is not this one's to resume", () async {
      final service = CallService(
        await clientWithOwnMembership(live: true, deviceId: 'OTHERPHONE'),
      );
      expect(await service.rejoinOffers(), isEmpty);
    });

    test('a ring is live only for the exact state event it names', () async {
      // A sender can hold several membership state keys (per-device and
      // legacy shapes). The discriminator must match the ring's OWN event,
      // not whichever non-empty entry the map yields first.
      final client = await clientWithOwnMembership(live: true);
      final service = CallService(client);
      final room = client.getRoomById(roomId)!;
      // A second, stale-but-non-empty state under another key.
      room.setState(
        Event(
          type: EventTypes.GroupCallMember,
          content: {
            'memberships': [
              {
                'call_id': 'old-call',
                'device_id': 'OLDDEV',
                'expires_ts': DateTime.now().millisecondsSinceEpoch + 300000,
              },
            ],
          },
          senderId: me,
          eventId: r'$old-key-state',
          originServerTs: DateTime.now(),
          room: room,
          stateKey: me,
        ),
      );
      expect(
        service.membershipEventIsCurrent(room, me, r'$own-membership'),
        isTrue,
      );
      expect(
        service.membershipEventIsCurrent(room, me, r'$old-key-state'),
        isTrue,
        reason: 'that entry is also genuinely current state',
      );
      expect(
        service.membershipEventIsCurrent(room, me, r'$replaced-long-ago'),
        isFalse,
      );
    });
  });
  group('whether a peer is still live in the call we are on', () {
    const peer = '@friend:fakeServer.notExisting';
    const me = '@test:fakeServer.notExisting';

    // A room per test. The ffi ':memory:' database is shared between clients
    // in one file, so a fixed room id carried the PREVIOUS test's membership
    // state into the next one -- and this group is precisely about reading
    // stale state correctly.
    var roomSeq = 0;

    Future<(CallService, Room)> withPeerState(
      List<Map<String, Object?>> memberships, {
      bool alsoRetractedDevice = false,
    }) async {
      final roomId = '!incall${roomSeq++}:fakeServer.notExisting';
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(user: me),
        deviceId: 'GHTYAJCE',
      );
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  for (var i = 0; i < memberships.length; i++)
                    MatrixEvent(
                      type: EventTypes.GroupCallMember,
                      content: {
                        'memberships': [memberships[i]],
                      },
                      senderId: peer,
                      eventId: '\$state$i',
                      originServerTs: DateTime.now(),
                      // A state key per device, which is how a room comes to
                      // hold several of one user's memberships.
                      stateKey:
                          'DEV$i'
                          '_$peer',
                    ),
                  // A second device of theirs that has hung up, for the case
                  // where one device leaves and another stays.
                  if (alsoRetractedDevice)
                    MatrixEvent(
                      type: EventTypes.GroupCallMember,
                      content: const {'memberships': <Object?>[]},
                      senderId: peer,
                      eventId: '\$retracted',
                      originServerTs: DateTime.now(),
                      stateKey: 'GONE_$peer',
                    ),
                ],
              ),
            },
          ),
        ),
      );
      return (CallService(client), client.getRoomById(roomId)!);
    }

    /// A peer whose member event carries [memberships] verbatim -- including
    /// the empty list a hangup writes.
    Future<(CallService, Room)> withRawPeerMemberships(
      List<Object?> memberships,
    ) async {
      final roomId = '!retract${roomSeq++}:fakeServer.notExisting';
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(user: me),
        deviceId: 'GHTYAJCE',
      );
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.GroupCallMember,
                    content: {'memberships': memberships},
                    senderId: peer,
                    eventId: '\$raw',
                    originServerTs: DateTime.now(),
                    stateKey: 'DEV0_$peer',
                  ),
                ],
              ),
            },
          ),
        ),
      );
      return (CallService(client), client.getRoomById(roomId)!);
    }

    /// A peer with two devices: a tablet that CRASHED in an earlier call and
    /// left an unexpired membership standing, and a phone that has since
    /// joined this call and hung up, retracting as it went.
    Future<(CallService, Room)> withStaleAndFresh() async {
      final roomId = '!stale${roomSeq++}:fakeServer.notExisting';
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(user: me),
        deviceId: 'GHTYAJCE',
      );
      final old = DateTime.now().subtract(const Duration(hours: 1));
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.GroupCallMember,
                    content: {
                      'memberships': [
                        {
                          'call_id': 'this-call',
                          'expires_ts': DateTime.now()
                              .add(const Duration(hours: 3))
                              .millisecondsSinceEpoch,
                        },
                      ],
                    },
                    senderId: peer,
                    eventId: '\$tablet',
                    originServerTs: old,
                    stateKey: 'TABLET_$peer',
                  ),
                  MatrixEvent(
                    type: EventTypes.GroupCallMember,
                    content: const {'memberships': <Object?>[]},
                    senderId: peer,
                    eventId: '\$phone',
                    originServerTs: DateTime.now(),
                    stateKey: 'PHONE_$peer',
                  ),
                ],
              ),
            },
          ),
        ),
      );
      return (CallService(client), client.getRoomById(roomId)!);
    }

    int inFuture() =>
        DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch;
    int inPast() => DateTime.now()
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;

    test('no call of our own means no opinion', () async {
      final (service, room) = await withPeerState([
        {'call_id': 'other', 'expires_ts': inFuture()},
      ]);
      expect(
        service.peerLiveInCurrentCall(room, peer),
        isTrue,
        reason: 'nothing to compare against; the SFU stays in charge',
      );
    });

    test(
      "a stale membership from an EARLIER call does not keep them alive",
      () async {
        // The device failure: the room holds one membership per device from
        // every call this session, and the broad "any non-empty" read saw a
        // departed peer as present for ever.
        final (service, room) = await withPeerState([
          {'call_id': 'older-call', 'expires_ts': inFuture()},
          {'call_id': 'this-call', 'expires_ts': inPast()},
        ]);
        service.adoptCallIdForTest('this-call');
        expect(service.peerLiveInCurrentCall(room, peer), isFalse);
      },
    );

    test('a live membership for THIS call keeps them present', () async {
      final (service, room) = await withPeerState([
        {'call_id': 'this-call', 'expires_ts': inFuture()},
      ]);
      service.adoptCallIdForTest('this-call');
      expect(service.peerLiveInCurrentCall(room, peer), isTrue);
    });

    test(
      'state that names no live membership for this call is them gone',
      () async {
        final (service, room) = await withPeerState([
          {'call_id': 'older-call', 'expires_ts': inFuture()},
        ]);
        service.adoptCallIdForTest('this-call');
        expect(
          service.peerLiveInCurrentCall(room, peer),
          isFalse,
          reason: 'they wrote state, and none of it is this call',
        );
      },
    );

    // Hanging up rewrites the member event to an EMPTY memberships list. That
    // retraction is the only evidence the other side gets that the departure
    // was deliberate; reading it as "no opinion" made a hangup look like a
    // crash and cost the peer a 20-second grace nobody was coming back from.
    test(
      'a peer who hung up has retracted, and a retraction is an answer',
      () async {
        final (service, room) = await withRawPeerMemberships([]);
        service.adoptCallIdForTest('this-call');
        expect(service.peerLiveInCurrentCall(room, peer), isFalse);
      },
    );

    test(
      'one device retracting does not remove a peer still on another',
      () async {
        final (service, room) = await withPeerState([
          {'call_id': 'this-call', 'expires_ts': inFuture()},
        ], alsoRetractedDevice: true);
        service.adoptCallIdForTest('this-call');
        expect(
          service.peerLiveInCurrentCall(room, peer),
          isTrue,
          reason: 'their other device is still in the call',
        );
      },
    );

    // The layer under the retraction rule: the call id IS the room id, so a
    // membership another of their devices left standing when it CRASHED in an
    // earlier call is indistinguishable from a live one, and it outvoted the
    // retraction the device they were actually using had just written.
    test(
      'a crashed device from an earlier call cannot outvote a retraction',
      () async {
        final (service, room) = await withStaleAndFresh();
        service.adoptCallIdForTest('this-call');
        expect(
          service.peerLiveInCurrentCall(room, peer),
          isTrue,
          reason: 'without a floor the stale membership still reads as live',
        );
        expect(
          service.peerLiveInCurrentCall(
            room,
            peer,
            notBefore: DateTime.now().subtract(const Duration(minutes: 2)),
          ),
          isFalse,
          reason: 'state older than this call cannot speak for it',
        );
      },
    );

    // "They retracted" and "they have not said anything yet" are opposites,
    // and the boolean read collapses them. Collapsing them is what let a
    // retraction be treated as silence one layer up: an ANSWERER whose first
    // sight of the caller's state is the retraction had never seen them live,
    // so the transition rule swallowed it and started a 20-second grace.
    test('a retraction and a silence are different answers', () async {
      final (retracted, room1) = await withRawPeerMemberships([]);
      retracted.adoptCallIdForTest('this-call');
      expect(
        retracted.peerPresenceInCurrentCall(room1, peer),
        PeerPresence.gone,
      );

      final (silent, room2) = await withPeerState([]);
      silent.adoptCallIdForTest('this-call');
      expect(
        silent.peerPresenceInCurrentCall(room2, peer),
        PeerPresence.unknown,
      );
    });

    // A redial moments after hanging up: the PREVIOUS call's retraction is
    // still the newest thing they wrote, and reading it as this call's
    // departure tore down a call that had just connected.
    // The caller joined BEFORE we answered, so their live membership is older
    // than our join. Gating the whole event on the departure floor skipped it,
    // presence fell to "cannot see", and the remembered sighting turned that
    // into "gone" -- calls died two seconds after being answered, which only
    // the browser suite could see.
    test(
      'their live membership counts even though it predates our join',
      () async {
        final (service, room) = await withPeerState([
          {'call_id': 'this-call', 'expires_ts': inFuture()},
        ]);
        service.adoptCallIdForTest('this-call');
        expect(
          service.peerPresenceInCurrentCall(
            room,
            peer,
            goneAfter: DateTime.now().add(const Duration(minutes: 1)),
          ),
          PeerPresence.live,
          reason: 'the departure floor must not hide their presence',
        );
      },
    );

    test(
      'a retraction from before we joined is not this call ending',
      () async {
        final (service, room) = await withRawPeerMemberships([]);
        service.adoptCallIdForTest('this-call');
        expect(
          service.peerPresenceInCurrentCall(room, peer),
          PeerPresence.gone,
          reason: 'with no floor it is simply the newest thing they wrote',
        );
        expect(
          service.peerPresenceInCurrentCall(
            room,
            peer,
            goneAfter: DateTime.now().add(const Duration(seconds: 1)),
          ),
          PeerPresence.unknown,
          reason: 'it predates our join, so it ended some earlier call',
        );
      },
    );

    test('a peer with no state at all is the only no opinion', () async {
      final (service, room) = await withPeerState([]);
      service.adoptCallIdForTest('this-call');
      expect(
        service.peerLiveInCurrentCall(room, peer),
        isTrue,
        reason: 'nothing written means their join may not have synced yet',
      );
    });
  });
  // Both scans run ONCE, at startup, which is exactly when the client is still
  // reading its room list out of the database after the reload they exist for.
  // Losing that race means iterating no rooms at all: the rejoin scan silently
  // offers nothing, and the missed-ring scan leaves a learner who reloaded
  // while their phone was ringing with no way to answer. An empty room list is
  // indistinguishable from nothing to find, so neither failure says anything.
  test('every startup scan waits for the room list first', () {
    final source = File(
      'lib/routes/chat/calls/call_service.dart',
    ).readAsStringSync();
    for (final scan in [
      'Future<List<RejoinOffer>> rejoinOffers()',
      'Future<List<IncomingCallNotification>> ringsMissed()',
    ]) {
      final at = source.indexOf(scan);
      expect(at, isNot(-1), reason: '$scan has been renamed; update this pin');
      final body = source.substring(at, at + 1400);
      expect(
        body,
        contains('await client.roomsLoading'),
        reason: '$scan must wait for the room list before it reads any room',
      );
    }
  });

  group('whether anybody else still holds the call', () {
    const me = '@test:fakeServer.notExisting';
    var seq = 0;

    Future<(CallService, Room)> withState(List<MatrixEvent> state) async {
      final roomId = '!hold${seq++}:fakeServer.notExisting';
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(user: me),
        deviceId: 'GHTYAJCE',
      );
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch',
          rooms: RoomsUpdate(join: {roomId: JoinedRoomUpdate(state: state)}),
        ),
      );
      return (CallService(client), client.getRoomById(roomId)!);
    }

    // The offer is raised in the first moments after a reload, which is
    // exactly when the client has not filled in room state yet. Reading that
    // silence as "the call is over" withdrew the offer -- and cleared the
    // breadcrumb behind it -- for a call that was alive and waiting.
    test('no call state yet is not the same as nobody holding it', () async {
      final (service, room) = await withState([]);
      expect(
        service.callHoldByAnother(room, r'$ours'),
        CallHold.unknown,
        reason: 'nothing has been read; that is not an answer',
      );
    });

    test('their state, holding nothing, is the call being over', () async {
      final (service, room) = await withState([
        MatrixEvent(
          type: EventTypes.GroupCallMember,
          content: const {'memberships': <Object?>[]},
          senderId: '@friend:fakeServer.notExisting',
          eventId: r'$theirs',
          originServerTs: DateTime.now(),
          stateKey: 'DEV_@friend:fakeServer.notExisting',
        ),
      ]);
      expect(service.callHoldByAnother(room, r'$ours'), CallHold.over);
    });

    // The person who CALLED us was already in the call while our phone rang,
    // so their membership is older than our answer. A floor set at our own
    // join threw it away and read the caller -- sitting in the call, waiting
    // -- as nobody, which withdrew the Return offer the instant it appeared
    // and cleared the breadcrumb with it.
    test('the caller, who joined before we answered, still counts', () async {
      final weJoined = DateTime.now().subtract(const Duration(minutes: 1));
      final theyJoined = weJoined.subtract(const Duration(seconds: 12));
      final (service, room) = await withState([
        MatrixEvent(
          type: EventTypes.GroupCallMember,
          content: {
            'memberships': [
              {
                'call_id': 'x',
                'expires_ts': DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch,
              },
            ],
          },
          senderId: '@friend:fakeServer.notExisting',
          eventId: r'$theirs',
          originServerTs: theyJoined,
          stateKey: 'DEV_@friend:fakeServer.notExisting',
        ),
      ]);
      expect(
        service.callHoldByAnother(room, r'$ours', notBefore: weJoined),
        CallHold.over,
        reason: 'a floor at our own join is what caused the bug',
      );
      expect(
        service.callHoldByAnother(
          room,
          r'$ours',
          notBefore: CallService.callFloorFrom(weJoined),
        ),
        CallHold.held,
        reason: 'one ring lifetime earlier admits the caller',
      );
    });

    test('their live membership is the call still being held', () async {
      final (service, room) = await withState([
        MatrixEvent(
          type: EventTypes.GroupCallMember,
          content: {
            'memberships': [
              {
                'call_id': 'x',
                'expires_ts': DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch,
              },
            ],
          },
          senderId: '@friend:fakeServer.notExisting',
          eventId: r'$theirs',
          originServerTs: DateTime.now(),
          stateKey: 'DEV_@friend:fakeServer.notExisting',
        ),
      ]);
      expect(service.callHoldByAnother(room, r'$ours'), CallHold.held);
    });
  });

  group('being busy is about the OTHER conversation', () {
    // Glare: both people press call at the same moment. The join claim is
    // taken the instant we tap, so their ring finds us "busy" -- and an
    // auto-decline then hung up a call that was coming up perfectly well,
    // for the room we were calling ourselves. Busy means in a call with
    // somebody ELSE; the glare tie-break decides a simultaneous one.
    test('a ring from the room we are already calling is not busy', () async {
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(
          user: '@test:fakeServer.notExisting',
        ),
        deviceId: 'GHTYAJCE',
      );
      final service = CallService(client);
      final source = File(
        'lib/routes/chat/calls/call_service.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('ring.event.room.id != _claimedRoomId'),
        reason: 'the busy predicate must exclude the room we are calling',
      );
      expect(
        source,
        contains('_claimedRoomId = room.id'),
        reason: 'and the claim must record which room it is for',
      );
      service.dispose();
    });
  });

  group('whether a ring in a room could be for us', () {
    // `isDirectChat` reads m.direct account data, which at cold start -- woken
    // by a call, or reloaded while one is ringing -- has not necessarily
    // loaded. Treating "not known to be a DM" as "not a DM" dropped real calls
    // at the one moment they matter, and the live ring stream never
    // redelivers.
    test('a two-person room qualifies before m.direct has loaded', () async {
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(
          user: '@test:fakeServer.notExisting',
        ),
        deviceId: 'GHTYAJCE',
      );
      final room = Room(
        id: '!pair:fakeServer.notExisting',
        client: client,
        summary: RoomSummary.fromJson({'m.joined_member_count': 2}),
      );
      expect(room.isDirectChat, isFalse, reason: 'no account data yet');
      expect(CallService.couldRingHere(room), isTrue);
    });

    test('a group room does not', () async {
      final client = await bareClient();
      final room = Room(
        id: '!group:fakeServer.notExisting',
        client: client,
        summary: RoomSummary.fromJson({'m.joined_member_count': 7}),
      );
      expect(CallService.couldRingHere(room), isFalse);
    });
  });

  group('whether the caller is still on the call they rang about', () {
    const caller = '@caller:fakeServer.notExisting';
    const me = '@test:fakeServer.notExisting';
    var seq = 0;

    /// A caller with two devices: a tablet that crashed in an earlier call and
    /// left a membership standing, and the phone that placed THIS ring and has
    /// since retracted.
    Future<(CallService, Room)> withCallerDevices({
      required bool phoneStillIn,
    }) async {
      final roomId = '!ring${seq++}:fakeServer.notExisting';
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(user: me),
        deviceId: 'GHTYAJCE',
      );
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.GroupCallMember,
                    content: const {
                      'memberships': [
                        {'call_id': 'x', 'device_id': 'TABLET'},
                      ],
                    },
                    senderId: caller,
                    eventId: '\$tablet',
                    originServerTs: DateTime.now(),
                    stateKey: '_${caller}_TABLET',
                  ),
                  MatrixEvent(
                    type: EventTypes.GroupCallMember,
                    content: {
                      'memberships': phoneStillIn
                          ? const [
                              {'call_id': 'x', 'device_id': 'PHONE'},
                            ]
                          : const <Object?>[],
                    },
                    senderId: caller,
                    eventId: '\$phone',
                    originServerTs: DateTime.now(),
                    stateKey: '_${caller}_PHONE',
                  ),
                ],
              ),
            },
          ),
        ),
      );
      return (CallService(client), client.getRoomById(roomId)!);
    }

    test(
      'a crashed second device cannot keep a cancelled ring alive',
      () async {
        final (service, room) = await withCallerDevices(phoneStillIn: false);
        expect(
          service.callerStillInCall(room, caller),
          isTrue,
          reason: 'the user-wide read still sees the stale tablet',
        );
        expect(
          service.callerStillInCall(room, caller, deviceId: 'PHONE'),
          isFalse,
          reason: 'the device that rang has retracted, so the ring is over',
        );
      },
    );

    // The caller's LAPTOP retracted when it ended an earlier call. That says
    // nothing about the PHONE ringing now -- and reading it as "that phone is
    // gone" dropped the recovered ring, so the callee saw nothing and the
    // caller rang out.
    test(
      'another device of theirs retracting does not silence this ring',
      () async {
        final roomId = '!laptop${seq++}:fakeServer.notExisting';
        final client = await bareClient();
        await client.login(
          LoginType.mLoginPassword,
          token: 'abcd',
          identifier: AuthenticationUserIdentifier(user: me),
          deviceId: 'GHTYAJCE',
        );
        await client.handleSync(
          SyncUpdate(
            nextBatch: 'batch',
            rooms: RoomsUpdate(
              join: {
                roomId: JoinedRoomUpdate(
                  state: [
                    MatrixEvent(
                      type: EventTypes.GroupCallMember,
                      content: const {'memberships': <Object?>[]},
                      senderId: caller,
                      eventId: r'$laptop',
                      originServerTs: DateTime.now(),
                      stateKey: '_${caller}_LAPTOP',
                    ),
                  ],
                ),
              },
            ),
          ),
        );
        final service = CallService(client);
        final room = client.getRoomById(roomId)!;
        expect(
          service.callerPresence(room, caller, deviceId: 'PHONE'),
          PeerPresence.unknown,
          reason: "the laptop's retraction is not the phone's",
        );
        expect(
          service.callerPresence(room, caller, deviceId: 'LAPTOP'),
          PeerPresence.gone,
          reason: 'it is very much the laptop\'s',
        );
      },
    );

    // The legacy key, which names no device at all, still speaks for the user.
    test(
      'a retraction under the bare user id speaks for every device',
      () async {
        final roomId = '!bare${seq++}:fakeServer.notExisting';
        final client = await bareClient();
        await client.login(
          LoginType.mLoginPassword,
          token: 'abcd',
          identifier: AuthenticationUserIdentifier(user: me),
          deviceId: 'GHTYAJCE',
        );
        await client.handleSync(
          SyncUpdate(
            nextBatch: 'batch',
            rooms: RoomsUpdate(
              join: {
                roomId: JoinedRoomUpdate(
                  state: [
                    MatrixEvent(
                      type: EventTypes.GroupCallMember,
                      content: const {'memberships': <Object?>[]},
                      senderId: caller,
                      eventId: r'$bare',
                      originServerTs: DateTime.now(),
                      stateKey: caller,
                    ),
                  ],
                ),
              },
            ),
          ),
        );
        final service = CallService(client);
        expect(
          service.callerPresence(
            client.getRoomById(roomId)!,
            caller,
            deviceId: 'PHONE',
          ),
          PeerPresence.gone,
        );
      },
    );

    test('the device that rang, still in the call, keeps ringing', () async {
      final (service, room) = await withCallerDevices(phoneStillIn: true);
      expect(
        service.callerStillInCall(room, caller, deviceId: 'PHONE'),
        isTrue,
      );
    });
  });

  group('whether a standing return offer still means anything', () {
    const me = '@test:fakeServer.notExisting';
    const peer = '@friend:fakeServer.notExisting';
    var n = 0;

    Future<(CallService, Room)> room({
      required bool ourEventStillNamesTheCall,
      required bool peerStillHolding,
    }) async {
      final roomId = '!offer${n++}:fakeServer.notExisting';
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(user: me),
        deviceId: 'GHTYAJCE',
      );
      final soon = DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch;
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.GroupCallMember,
                    content: {
                      'memberships': ourEventStillNamesTheCall
                          ? [
                              {
                                'call_id': 'the-call',
                                'device_id': 'GHTYAJCE',
                                'expires_ts': soon,
                              },
                            ]
                          : <Map<String, Object?>>[],
                    },
                    senderId: me,
                    eventId: r'$mine',
                    originServerTs: DateTime.now(),
                    stateKey: 'GHTYAJCE_$me',
                  ),
                  MatrixEvent(
                    type: EventTypes.GroupCallMember,
                    content: {
                      'memberships': peerStillHolding
                          ? [
                              {
                                'call_id': 'the-call',
                                'device_id': 'THEIRS',
                                'expires_ts': soon,
                              },
                            ]
                          : <Map<String, Object?>>[],
                    },
                    senderId: peer,
                    eventId: r'$theirs',
                    originServerTs: DateTime.now(),
                    stateKey: 'THEIRS_$peer',
                  ),
                ],
              ),
            },
          ),
        ),
      );
      return (CallService(client), client.getRoomById(roomId)!);
    }

    test(
      'the offer stands while the other person is still on the call',
      () async {
        final (service, r) = await room(
          ourEventStillNamesTheCall: true,
          peerStillHolding: true,
        );
        expect(service.callStillHeldByAnother(r, r'\$mine'), isTrue);
      },
    );

    test('it stands even when OUR membership was already retracted', () async {
      // The reload this offer exists for is exactly when the server empties
      // our entry; requiring it withdrew the offer the instant it appeared.
      final (service, r) = await room(
        ourEventStillNamesTheCall: false,
        peerStillHolding: true,
      );
      expect(service.callStillHeldByAnother(r, r'\$mine'), isTrue);
    });

    test('it goes once nobody else is holding the call', () async {
      final (service, r) = await room(
        ourEventStillNamesTheCall: true,
        peerStillHolding: false,
      );
      expect(service.callStillHeldByAnother(r, r'\$mine'), isFalse);
    });
  });

  group('a second device of the same account', () {
    const me = '@test:fakeServer.notExisting';
    const peer = '@friend:fakeServer.notExisting';
    var seq = 0;

    /// The ring goes out at [ringAt]; our other device's membership is
    /// written at [siblingWroteAt]. The call id is the ROOM id in this app,
    /// so ONLY that ordering can tell a sibling answering THIS call from the
    /// rows every earlier call in the room left behind.
    Future<(CallService, Room, DateTime)> roomWith({
      required Duration siblingWroteAgo,
      required Duration ringSentAgo,
      required bool siblingPresent,
      bool siblingIsThisDevice = false,
      bool siblingExpired = false,
    }) async {
      final roomId = '!twodev${seq++}:fakeServer.notExisting';
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(user: me),
        deviceId: 'THISPHONE',
      );
      final now = DateTime.now();
      final expires = siblingExpired
          ? now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch
          : now.add(const Duration(minutes: 5)).millisecondsSinceEpoch;
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  if (siblingPresent)
                    MatrixEvent(
                      type: EventTypes.GroupCallMember,
                      content: {
                        'memberships': [
                          {
                            'call_id': roomId,
                            'device_id': siblingIsThisDevice
                                ? client.deviceID!
                                : 'OTHERPHONE',
                            'expires_ts': expires,
                          },
                        ],
                      },
                      senderId: me,
                      eventId: r'$sibling',
                      originServerTs: now.subtract(siblingWroteAgo),
                      stateKey: 'OTHERPHONE_$me',
                    ),
                  MatrixEvent(
                    type: EventTypes.GroupCallMember,
                    content: {
                      'memberships': [
                        {
                          'call_id': roomId,
                          'device_id': 'CALLERDEV',
                          'expires_ts': expires,
                        },
                      ],
                    },
                    senderId: peer,
                    eventId: r'$caller',
                    originServerTs: now.subtract(ringSentAgo),
                    stateKey: 'CALLERDEV_$peer',
                  ),
                ],
              ),
            },
          ),
        ),
      );
      return (
        CallService(client),
        client.getRoomById(roomId)!,
        now.subtract(ringSentAgo),
      );
    }

    test('a sibling that joined AFTER the ring stops this device', () async {
      final (service, room, ringAt) = await roomWith(
        ringSentAgo: const Duration(seconds: 20),
        siblingWroteAgo: const Duration(seconds: 5),
        siblingPresent: true,
      );
      expect(service.answeredOnAnotherDevice(room, ringAt), isTrue);
    });

    test('a row left by an EARLIER call does not', () async {
      // The regression this pins: the call id is the room id, so an old
      // membership matched it perfectly and every incoming ring was
      // dismissed the instant it arrived -- calls became unanswerable.
      final (service, room, ringAt) = await roomWith(
        ringSentAgo: const Duration(seconds: 10),
        siblingWroteAgo: const Duration(minutes: 30),
        siblingPresent: true,
      );
      expect(service.answeredOnAnotherDevice(room, ringAt), isFalse);
    });

    test('nobody of ours in the call means this one keeps ringing', () async {
      final (service, room, ringAt) = await roomWith(
        ringSentAgo: const Duration(seconds: 10),
        siblingWroteAgo: Duration.zero,
        siblingPresent: false,
      );
      expect(service.answeredOnAnotherDevice(room, ringAt), isFalse);
    });

    test('our OWN device joining is not "somebody else answered"', () async {
      final (service, room, ringAt) = await roomWith(
        ringSentAgo: const Duration(seconds: 20),
        siblingWroteAgo: const Duration(seconds: 5),
        siblingPresent: true,
        siblingIsThisDevice: true,
      );
      expect(service.answeredOnAnotherDevice(room, ringAt), isFalse);
    });

    test('an expired sibling membership is nobody', () async {
      final (service, room, ringAt) = await roomWith(
        ringSentAgo: const Duration(seconds: 20),
        siblingWroteAgo: const Duration(seconds: 5),
        siblingPresent: true,
        siblingExpired: true,
      );
      expect(service.answeredOnAnotherDevice(room, ringAt), isFalse);
    });
  });

  /// The identity every writer in a call agrees on is this device's membership
  /// event id -- the caller holds it as its own echo, the callee reads it off
  /// the ring it answered. Two calls that derive the SAME one are two calls of
  /// which only the first is ever written: the transcript's transaction id is
  /// built from that key, a homeserver collapses a repeated transaction id from
  /// the same device, and the second call's speech is absorbed as a duplicate
  /// of a call that had already ended -- reaching the room as nothing at all,
  /// with success returned to every writer. The card lands under the shared key
  /// too, and the reader keeps the first, so the second call is drawn with the
  /// first one's duration.
  ///
  /// Room state cannot answer which membership belongs to which call. The group
  /// call id IS the room id, so every membership of ours in this room matches
  /// the current call; a membership stands for minutes; and a leave leaves
  /// state only when its echo arrives. A call that reads state before its own
  /// membership has echoed therefore reads the PREVIOUS call's — and nothing
  /// the membership carries tells the two apart, since only `expires_ts` moves
  /// between two writes and it is the device wall clock, which can step
  /// backwards.
  ///
  /// So the anchor is not derived from state at all: `enter()` returns the
  /// event id the server assigned to the membership THAT join published, and
  /// that is what a call keys on. What these pin is that the id comes from the
  /// publish and from nowhere else — no state, no clock, and no enter belonging
  /// to a call that is over.
  group('the membership that identifies a call', () {
    const me = '@test:fakeServer.notExisting';
    var seq = 0;

    /// Puts one membership of ours into [roomId]'s state under [eventId].
    ///
    /// There is ONE state event per account and device, so a later membership
    /// REPLACES this one and takes a fresh event id. That is what lets the id
    /// identify a call at all, and it is exactly what a read taken before the
    /// replacement has echoed throws away.
    /// [stampedAt] is when the DEVICE wrote it. The SDK stamps every membership
    /// it publishes with `now + expireTsBumpDuration` off this device's own
    /// clock, so the stamp is the only field that moves between two writes --
    /// and it moves with a clock that can step backwards, which is why nothing
    /// here is allowed to decide anything by it.
    Future<void> publishMembership(
      Client client,
      String roomId,
      String eventId, {
      DateTime? stampedAt,
    }) => client.handleSync(
      SyncUpdate(
        nextBatch: 'batch-$eventId',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              state: [
                MatrixEvent(
                  type: EventTypes.GroupCallMember,
                  content: {
                    'memberships': [
                      {
                        'call_id': 'call-id',
                        'application': 'm.call',
                        'scope': 'm.room',
                        'foci_active': [
                          {
                            'type': 'livekit',
                            'livekit_alias': 'alias',
                            'livekit_service_url': 'http://sfu:7980',
                          },
                        ],
                        'device_id': 'GHTYAJCE',
                        'expires_ts': (stampedAt ?? DateTime.now())
                            .add(CallTimeouts().expireTsBumpDuration)
                            .millisecondsSinceEpoch,
                        'membershipID': 'ours',
                      },
                    ],
                  },
                  senderId: me,
                  eventId: eventId,
                  originServerTs: DateTime.now(),
                  stateKey: me,
                ),
              ],
            ),
          },
        ),
      ),
    );

    /// When the CALL BEFORE this one stamped its writes: a moment ago, so its
    /// membership is nowhere near expiring and is refused on what it says about
    /// itself rather than on age.
    DateTime beforeThisCall() =>
        DateTime.now().subtract(const Duration(seconds: 5));

    /// The same call's writes as this device would stamp them AFTER its clock
    /// has stepped backward: the previous call's membership carrying a stamp
    /// no write this call makes can reach, so it looks newer than the call that
    /// replaced it.
    DateTime afterThisCall() => DateTime.now().add(const Duration(seconds: 5));

    /// A service about to place a call into a room where the PREVIOUS call's
    /// membership is still standing -- a redial whose hangup has been written
    /// but whose echo has not come back.
    Future<(_JoinSteps, Room)> redialing() async {
      final roomId = '!anchor${seq++}:fakeServer.notExisting';
      final client = await bareClient();
      await client.login(
        LoginType.mLoginPassword,
        token: 'abcd',
        identifier: AuthenticationUserIdentifier(user: me),
        deviceId: 'GHTYAJCE',
      );
      await publishMembership(
        client,
        roomId,
        r'$earlier-call',
        stampedAt: beforeThisCall(),
      );
      return (
        _JoinSteps(client, focusDiscovery: _FixedFocus()),
        client.getRoomById(roomId)!,
      );
    }

    /// A session for [room] that publishes nothing of its own, so what
    /// `announce` is looking at is only ever what the test put in state.
    _LeavingSession sessionFor(_JoinSteps calls, Room room) => _LeavingSession(
      client: calls.client,
      room: room,
      voip: calls.voip,
      backend: LiveKitBackend(
        livekitServiceUrl: 'http://sfu:7980',
        livekitAlias: 'alias',
        e2eeEnabled: false,
      ),
      groupCallId: 'call-id',
      application: 'm.call',
      scope: 'm.room',
    );

    test('is never the one an earlier call left standing', () async {
      final (calls, room) = await redialing();
      await calls.join(room);
      expect(
        calls.membershipEventIdIn(calls.joinAttempt),
        isNull,
        reason:
            'this call has published nothing yet, so it has no identity yet. '
            'Answering with the earlier call\'s membership hands the redial '
            'the very key that call already wrote its transcript under',
      );
    });

    test('is the one this call published, with no echo to wait for', () async {
      final (calls, room) = await redialing();
      calls.adoptSessionForTest(sessionFor(calls, room));

      expect(await calls.announce(), r'$this-call');
      expect(
        calls.membershipEventIdIn(calls.joinAttempt),
        r'$this-call',
        reason:
            'refusing what this call did not publish must not amount to '
            'refusing everything: a call with no anchor never rings and is '
            'never written. This is the read a device that merely JOINED '
            "takes, not announce's own return -- and it answers straight "
            'away, because the id came back with the write rather than with '
            'its echo',
      );
    });

    // A membership state event is ONE slot per account and device: every write
    // replaces the last and takes a new event id. So the call before this one
    // can still have a write in flight -- its refresh, issued before the hangup
    // cancelled the timer -- and that write echoes back AFTER this call has
    // begun, carrying an event id this call has never seen. Anything that
    // decides by "was this here when I started" accepts it; anything that reads
    // state at all is still deciding by what happens to be standing there.
    test('is never a late write from the call before it', () async {
      final (calls, room) = await redialing();
      calls.adoptSessionForTest(sessionFor(calls, room));

      expect(await calls.announce(), r'$this-call', reason: 'precondition');

      // The previous call's refresh, in flight when the hangup ran, echoing
      // back only now -- and taking the room's one membership slot, so state no
      // longer mentions this call's membership at all.
      await publishMembership(
        calls.client,
        room.id,
        r'$earlier-call-refreshed',
        stampedAt: beforeThisCall(),
      );

      expect(
        calls.membershipEventIdIn(calls.joinAttempt),
        r'$this-call',
        reason:
            'the anchor is what this call published, and a write from the '
            "call before it cannot move that however late it lands. Adopting "
            "it keys this call's transcript and card to the call before it -- "
            'the very collision this refuses, reached by a later road',
      );
    });

    test('is never a late write that lands while the join is running', () async {
      final (calls, room) = await redialing();
      final session = sessionFor(calls, room);
      // The join held open, so the late write really does land INSIDE it
      // rather than before it or after it.
      session.enterGate = Completer<void>();
      calls.adoptSessionForTest(session);

      final announcing = calls.announce();
      await pumpEventQueue();
      // The previous call's refresh, arriving while this call's own publish is
      // still on the wire.
      await publishMembership(
        calls.client,
        room.id,
        r'$earlier-call-refreshed',
        stampedAt: beforeThisCall(),
      );
      await pumpEventQueue();
      session.enterGate!.complete();

      expect(
        await announcing,
        r'$this-call',
        reason:
            'announce returns the id every writer in this call keys on, and '
            'that id came back from this call\'s own write. The refresh that '
            'landed inside the join belongs to the call before it',
      );
    });

    // And the line is drawn at the PUBLISH, not at the start of the call. The
    // two are not the same instant: announce parks until every leave the
    // previous call is still issuing has finished, and that call's refresh
    // timer can put another write out inside that wait.
    test(
      'is never a write the call before it made while this one waited',
      () async {
        final (calls, room) = await redialing();
        calls.adoptSessionForTest(sessionFor(calls, room));
        // The previous call's leave, still running: announce holds here.
        final lastCallsLeave = Completer<void>();
        calls.setPendingLeaveForTest(lastCallsLeave.future);

        final announcing = calls.announce();
        await pumpEventQueue();
        // Its refresh, issued NOW -- after this call began, and still before
        // this call has published anything of its own.
        await publishMembership(
          calls.client,
          room.id,
          r'$earlier-call-refreshed',
        );
        await Future.delayed(const Duration(milliseconds: 50));

        lastCallsLeave.complete();
        await pumpEventQueue();

        expect(
          await announcing,
          r'$this-call',
          reason:
              'the question is what THIS call published, and it had published '
              'nothing while it was still waiting for the last one to let go',
        );
      },
    );

    test('is what the join returned, not what is already there', () async {
      final (calls, room) = await redialing();
      final session = sessionFor(calls, room);
      calls.adoptSessionForTest(session);

      // The enter writes nothing into room state here, which is the honest
      // model: a real one publishes the membership and state learns of it only
      // when the write echoes back, long after the id itself came home.
      final announced = await calls.announce();

      expect(
        session.enters,
        1,
        reason:
            'precondition: this call really did publish a membership of its '
            'own, so the id below is a publish that answered rather than a '
            'question that was never asked',
      );
      expect(
        announced,
        r'$this-call',
        reason:
            'announce returns the id every writer in this call will key on; '
            'returning the one already in state gives the redial the previous '
            "call's key and silently destroys this call's transcript",
      );
    });

    // The device wall clock is not monotonic. A backward step BETWEEN the
    // previous call's write and this call's publish leaves that older
    // membership stamped LATER than anything this call can stamp -- unexpired,
    // same call id, and ahead of any floor a comparison of stamps could draw.
    // That is what defeated the stamp floor this replaces, and it is why the
    // anchor no longer comes from a stamp, or from state, at all.
    test('is never the previous membership after the clock steps back', () async {
      final (calls, room) = await redialing();
      calls.adoptSessionForTest(sessionFor(calls, room));
      // The clock steps backward: the call before this one wrote its membership
      // with a stamp this call cannot reach.
      await publishMembership(
        calls.client,
        room.id,
        r'$earlier-call',
        stampedAt: afterThisCall(),
      );

      expect(
        await calls.announce(),
        isNot(r'$earlier-call'),
        reason:
            'a membership stamped ahead of this call is still the call before '
            "it. Adopting it hands the redial the key that call's transcript "
            'was already written under',
      );
      expect(
        calls.membershipEventIdIn(calls.joinAttempt),
        r'$this-call',
        reason: 'and what it has instead is the id its own publish was given',
      );
    });

    // F2. An enter OUTLIVES its call: retract waits [_settleEnterWithin] for one
    // and then leaves anyway, so a redial can begin while the previous call's
    // enter is still settling. The redial must publish its OWN membership. The
    // earlier structure waited on that in-flight enter and returned its result,
    // so the redial got either the previous call's id or -- once the owner guard
    // refused it -- no anchor at all, its whole transcript lost with no alarm.
    test('is its own even when an earlier call\'s enter is still in flight', () async {
      final (calls, room) = await redialing();
      // Call A's enter never settles on its own, so it is still in flight -- and
      // still in the service's entering slot -- when the redial begins.
      final sessionA = sessionFor(calls, room)
        ..publishes = r'$a-call'
        ..enterGate = Completer<void>();
      calls.adoptSessionForTest(sessionA);
      final aAnnouncing = calls.announce();
      await pumpEventQueue();
      expect(
        sessionA.enters,
        1,
        reason: 'precondition: A\'s enter is in flight',
      );

      // The redial. A fresh session, as one is once A's leave has removed A's
      // from the registry. It begins on top while A's enter is still out.
      final sessionB = sessionFor(calls, room)..publishes = r'$b-call';
      calls.adoptSessionForTest(sessionB);
      final bAttempt = calls.joinAttempt;

      // B announces while A's enter is still the one in the service's slot. With
      // the fix B ignores it and publishes its own membership at once, so B's
      // answer does not depend on A's gate; A's enter is released here only so
      // that, were the slot NOT owner-scoped, B's wait on it would unblock and
      // reveal the null it was handed rather than hanging the test.
      final bAnnouncing = calls.announce();
      sessionA.enterGate!.complete();
      expect(
        await bAnnouncing,
        r'$b-call',
        reason:
            'B published its own membership and anchored on the id THAT write '
            'returned. Waiting on A\'s in-flight enter instead would give B '
            'A\'s id, or -- once the owner guard refuses it -- no anchor at '
            'all, and B\'s whole transcript would be lost with nothing logged',
      );
      expect(sessionB.enters, 1, reason: 'B entered its OWN session');
      expect(calls.membershipEventIdIn(bAttempt), r'$b-call');

      // A's own announce, resuming after B superseded it, reports NEITHER its
      // own dead enter's id nor -- the subtler trap -- the redial's. Its late
      // write is refused, so it cannot overwrite the live call's anchor.
      expect(
        await aAnnouncing,
        isNull,
        reason:
            'a superseded announce returns null, never its own dead id and '
            "never the redial's",
      );
      expect(calls.membershipEventIdIn(bAttempt), r'$b-call');
    });

    // announce() itself RETURNS the anchor, so its return is an anchor-producing
    // path like the read and the write. A call whose announce is still awaiting
    // its own enter when a redial supersedes it must get null back -- not the
    // id the field now holds, which is the redial's. The enter's [_anchorOn]
    // already refuses to STORE the dead call's id; this is the same refusal on
    // the way OUT, and without it A and B key their card and transcript on one
    // membership -- the collision, reached through announce's return.
    test('announce returns null to a call a redial has superseded', () async {
      final (calls, room) = await redialing();
      final sessionA = sessionFor(calls, room)
        ..publishes = r'$a-call'
        ..enterGate = Completer<void>();
      calls.adoptSessionForTest(sessionA);
      final aAnnouncing = calls.announce();
      await pumpEventQueue();

      // Redial B supersedes while A's announce is still parked on its enter.
      final sessionB = sessionFor(calls, room)..publishes = r'$b-call';
      calls.adoptSessionForTest(sessionB);
      final bAttempt = calls.joinAttempt;
      expect(
        await calls.announce(),
        r'$b-call',
        reason: 'precondition: B is current and anchored on its own id',
      );

      // A's enter settles now. _anchorOn refuses A's id (A no longer owns), and
      // A's announce, resuming, must not hand back the id the field holds -- B's.
      sessionA.enterGate!.complete();
      expect(
        await aAnnouncing,
        isNull,
        reason:
            'a superseded announce returns null, never the redial\'s id. '
            'Returning the field ungated hands the dead call B\'s membership, '
            'and A and B key their transcript and card on one id',
      );
      expect(
        calls.membershipEventIdIn(bAttempt),
        r'$b-call',
        reason: 'and the live call keeps its own',
      );
    });

    test('is never the one the call before it published', () async {
      final (calls, room) = await redialing();
      calls.adoptSessionForTest(
        sessionFor(calls, room)..publishes = r'$a-call',
      );
      final aAttempt = calls.joinAttempt;
      expect(await calls.announce(), r'$a-call', reason: 'precondition');

      // The next call in this room begins. It has published nothing of its own
      // yet, and the id the call before it was given is not available to it --
      // not to its own attempt, and not to the earlier call's either.
      calls.adoptSessionForTest(sessionFor(calls, room));
      final bAttempt = calls.joinAttempt;

      expect(
        calls.membershipEventIdIn(bAttempt),
        isNull,
        reason:
            'an anchor is a fact about ONE call. Carrying it into the next one '
            'is the redial collision itself: two calls deriving the same key, '
            'of which only the first is ever written',
      );
      expect(
        calls.membershipEventIdIn(aAttempt),
        isNull,
        reason: 'and the call before it is gone; its attempt gets null too',
      );
    });

    // F1. A stale ActiveCall reads at teardown for an anchor it never captured.
    // If a redial has taken its place in the same room by then, a room-keyed
    // read hands it the redial's id -- two calls keyed on one membership, the
    // collision reached through the READ. Addressing the read to the attempt
    // that owns the call is what refuses it.
    test('is not answered to the call a redial has replaced', () async {
      final (calls, room) = await redialing();
      calls.adoptSessionForTest(
        sessionFor(calls, room)..publishes = r'$a-call',
      );
      final aAttempt = calls.joinAttempt;
      expect(
        await calls.announce(),
        r'$a-call',
        reason: 'precondition: A live',
      );

      // Redial B in the SAME room, publishing its own id.
      calls.adoptSessionForTest(
        sessionFor(calls, room)..publishes = r'$b-call',
      );
      final bAttempt = calls.joinAttempt;
      expect(
        await calls.announce(),
        r'$b-call',
        reason: 'precondition: B live',
      );

      expect(
        calls.membershipEventIdIn(aAttempt),
        isNull,
        reason:
            'A reads with its OWN attempt at teardown; the service holds B now, '
            'and answering with B\'s id keys A\'s late transcript and card on '
            'B\'s membership -- the collision, reached through the read',
      );
      expect(
        calls.membershipEventIdIn(bAttempt),
        r'$b-call',
        reason: 'while B, the live call, still gets its own',
      );
    });

    // The poll this replaced re-checked disposal on every attempt, so a logout
    // landing inside the wait stopped the announce rather than answering after
    // it. There is no poll left to make that check, and the wait is still there.
    test('is not answered for an account that has logged out', () async {
      final (calls, room) = await redialing();
      final session = sessionFor(calls, room);
      // The join held open, so the logout lands INSIDE the wait rather than
      // before it.
      session.enterGate = Completer<void>();
      calls.adoptSessionForTest(session);

      final announcing = calls.announce();
      await pumpEventQueue();
      final disposing = calls.dispose();
      session.enterGate!.complete();

      await expectLater(
        announcing,
        throwsStateError,
        reason:
            'answering here hands a call identity to a service the account '
            'has already been torn out of, and every read it reaches for goes '
            'through a VoIP instance that disposal has dropped',
      );
      await disposing;
    });

    test('is nothing when the join published no membership', () async {
      final (calls, room) = await redialing();
      final session = sessionFor(calls, room);
      // What the SDK returns when it wrote nothing: a leave already in flight
      // on the session suppresses the write without changing the state enter
      // checks.
      session.publishes = null;
      calls.adoptSessionForTest(session);

      expect(
        await calls.announce(),
        isNull,
        reason:
            'a call that published no membership has no identity, and saying '
            'so is the whole of the failure: the transcript writer logs and '
            'writes nothing rather than writing under a key it guessed',
      );
      expect(calls.membershipEventIdIn(calls.joinAttempt), isNull);
    });

    // The SDK writes the membership FIRST and only then runs the rest of
    // entering, so a throw from any of those later steps leaves a membership
    // that may well be live -- under an id the caller never learns.
    test(
      'is unknown, not absent, when the join throws after writing',
      () async {
        final (calls, room) = await redialing();
        final session = sessionFor(calls, room);
        session.enterThrows = StateError('the delegate refused the call');
        calls.adoptSessionForTest(session);

        await expectLater(calls.announce(), throwsA(isA<StateError>()));
        expect(
          calls.membershipEventIdIn(calls.joinAttempt),
          isNull,
          reason: 'the key is unknown, and a guessed one is worse than none',
        );

        await expectLater(calls.retract(), completion(isTrue));
        expect(
          session.leaves,
          1,
          reason:
              'and the membership is taken back, because a join that failed '
              'after its write is not the same thing as a call that never '
              'published anything',
        );
      },
    );
  });
}

/// A room that accepts any send and remembers the transaction ids used.
class _TxidRoom extends Room {
  _TxidRoom({required super.id, required super.client});

  final List<String?> txids = [];

  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    txids.add(txid);
    return '\$ring';
  }
}

/// A backend whose release throws, so `leave()` fails at a step that runs
/// AFTER the membership has already been written away.
class _ThrowsAfterTheWrite extends LiveKitBackend {
  _ThrowsAfterTheWrite()
    : super(
        livekitServiceUrl: 'http://sfu:7980',
        livekitAlias: 'alias',
        e2eeEnabled: false,
      );

  @override
  Future<void> dispose(GroupCallSession groupCall) async =>
      throw StateError('releasing the backend failed');
}

/// A homeserver that advertises a focus, without the `.well-known` round trip —
/// so a test about the steps AFTER discovery does not have to serve one.
class _FixedFocus extends RtcFocusDiscovery {
  @override
  Future<RtcFocus?> discover(Uri homeserver) async =>
      const RtcFocus(serviceUrl: 'http://sfu:7980');
}

/// Records whether a session was handed back, and whether anything entered it,
/// without a live SFU behind either.
class _LeavingSession extends GroupCallSession {
  _LeavingSession({
    required super.client,
    required super.room,
    required super.voip,
    required super.backend,
    required super.groupCallId,
    required super.application,
    required super.scope,
  });

  int leaves = 0;
  int enters = 0;

  /// Holds a leave open, so what the service does WHILE one is still in flight
  /// is observable. Null means it answers at once, which is what every test
  /// that does not care about the window gets.
  Completer<void>? leaveGate;

  /// What each successive leave does, oldest first. An entry is thrown by the
  /// attempt that takes it; once the list is empty every leave succeeds.
  ///
  /// A leave that FAILS is the only way into the retract's retry loop, and the
  /// sleep between its attempts is a window nothing else can reach.
  final List<Object> leaveThrowsInOrder = [];

  @override
  Future<void> leave() async {
    leaves++;
    await leaveGate?.future;
    if (leaveThrowsInOrder.isNotEmpty) throw leaveThrowsInOrder.removeAt(0);
  }

  /// What a real `enter()` hands back: the event id the server assigned to the
  /// membership THIS join published. Null models the SDK's own null, a join
  /// that wrote no membership at all.
  String? publishes = r'$this-call';

  /// Holds an enter open, so what the service does WHILE one is still in flight
  /// is observable — a second call joining it, a state write landing inside it.
  Completer<void>? enterGate;

  /// Thrown by the enter once the gate has opened. The SDK writes the
  /// membership FIRST and only then does the work that can throw, so this
  /// models the case that matters: a membership that may well be live, under an
  /// id the caller never learns.
  Object? enterThrows;

  @override
  Future<String?> enter({WrappedMediaStream? stream}) async {
    enters++;
    await enterGate?.future;
    final failure = enterThrows;
    if (failure != null) throw failure;
    return publishes;
  }
}

/// A token failure that has nothing to do with the join being abandoned, so the
/// two can be told apart by type.
class _TokenRefused implements Exception {
  const _TokenRefused();
}

/// Drives the two network steps of joining, so the checks BETWEEN them are
/// observable. Neither step can be stood up here: one needs a live SFU and the
/// other the choreographer.
class _JoinSteps extends CallService {
  _JoinSteps(super.client, {super.focusDiscovery, super.leaveWithin});

  final List<String> steps = [];

  /// Run INSIDE the step it is named for, so a hangup lands exactly where the
  /// ordering under test puts it.
  void Function()? duringFetch;
  void Function()? duringToken;

  Object? tokenThrows;

  /// The first session this fetched, for the tests that only ever use one room.
  _LeavingSession? session;

  /// One session per ROOM, which is how the real one is fetched: a direct
  /// message holds at most one call, so two joins in the same room are handed
  /// the very same object and two joins in different rooms are not.
  final Map<String, _LeavingSession> sessionsByRoom = {};

  @override
  Future<GroupCallSession> fetchSession(Room room, RtcFocus focus) async {
    steps.add('session');
    final fetched = sessionsByRoom.putIfAbsent(
      room.id,
      () => _LeavingSession(
        client: client,
        room: room,
        voip: voip,
        backend: focus.backendForRoom(room.id),
        groupCallId: 'call-id',
        application: 'm.call',
        scope: 'm.room',
      ),
    );
    session ??= fetched;
    duringFetch?.call();
    return fetched;
  }

  @override
  Future<CallToken> requestToken(Room room, RtcFocus focus) async {
    steps.add('token');
    duringToken?.call();
    final failure = tokenThrows;
    if (failure != null) throw failure;
    return const CallToken(jwt: 'jwt', url: 'ws://sfu');
  }
}

/// Discovery held open so a test can dispose the service mid-lookup.
class _HeldDiscovery extends RtcFocusDiscovery {
  final Completer<void> gate;
  _HeldDiscovery(this.gate);

  @override
  Future<RtcFocus?> discover(Uri homeserver) async {
    await gate.future;
    return const RtcFocus(serviceUrl: 'http://sfu:7980');
  }
}
