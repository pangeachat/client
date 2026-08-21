import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
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
