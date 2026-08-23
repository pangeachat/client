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
          service.membershipEventIdIn(room),
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
        'pangea.call.breadcrumb':
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
        'pangea.call.breadcrumb':
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
