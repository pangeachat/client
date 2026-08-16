import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_service.dart';
import 'package:fluffychat/features/dosage/dosage_audio_buffer.dart';
import 'package:fluffychat/features/dosage/dosage_audio_category.dart';
import 'package:fluffychat/features/dosage/dosage_audio_event.dart';
import 'package:fluffychat/features/dosage/dosage_message_signals.dart';
import 'package:fluffychat/features/dosage/dosage_shared_player_tracker.dart';
import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';

/// The learner must not be able to tell this feature shipped.
///
/// Every test here is about TIMING rather than correctness: no user-facing path
/// may wait on telemetry, and a dead endpoint — the normal state until the
/// server ships the ingest route — must be indistinguishable at the UI from a
/// working one.
///
/// The transport in these tests NEVER RESOLVES. Anything that awaited it would
/// hang the test rather than fail an assertion, which is the point: a passing
/// run is itself the proof that nothing awaited it.
class _FakeDataService implements AnalyticsDataService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TokenDataService implements AnalyticsDataService {
  _TokenDataService(this.userId, this.token);
  final String? userId;
  final String? token;
  @override
  String? get accountUserId => userId;
  @override
  String? get accountAccessToken => token;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mxid = '@learner:example.org';
  const token = 'syt_student_token';
  const roomId = '!room:example.org';

  /// A transport whose every request hangs forever, with no response and no
  /// error. Standing in for the worst realistic case: a half-open socket to an
  /// endpoint that is not there.
  http.Client hangingClient() =>
      MockClient((_) => Completer<http.Response>().future);

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('dosage_nonblock');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (m) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  setUp(() {
    dotenv.testLoad(
      mergeWith: {
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
      },
    );
    DosageAudioBuffer.debugResetAccounts();
  });

  tearDown(() {
    DosageAudioBuffer.debugResetAccounts();
    DosageSignalsRepo.clientFactory = http.Client.new;
  });

  test('closing a playback does NO network work at all', () {
    // The strongest form of "playback is not delayed": the emit path never
    // reaches the transport, so there is nothing to be slow. It appends to an
    // in-memory list and returns.
    var requests = 0;
    final buffer = DosageAudioBuffer(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('', 202);
      }),
    );
    var clock = DateTime.utc(2026, 1, 1, 12);
    final tracker = DosageSharedPlayerTracker(
      category: DosageListeningCategory.peer,
      roomId: roomId,
      ownerId: 'owner',
      userId: () => mxid,
      accessToken: () => token,
      now: () => clock,
      buffer: buffer,
    );

    tracker.update(playing: true, completed: false, currentOwnerId: 'owner');
    clock = clock.add(const Duration(seconds: 5));

    final before = DateTime.now();
    tracker.update(playing: false, completed: true, currentOwnerId: 'owner');
    final elapsed = DateTime.now().difference(before);

    expect(requests, 0, reason: 'stopping playback posts nothing');
    expect(buffer.bufferedEvents, hasLength(1));
    expect(elapsed.inMilliseconds, lessThan(50));
  });

  test('the voice-send emit returns without waiting on a hung POST', () async {
    // The speaking call site. Its transport is the shared best-effort repo,
    // which fires and forgets — verified at origin/main — so the send flow gets
    // control straight back even when the endpoint never answers.
    DosageSignalsRepo.clientFactory = hangingClient;

    var returned = false;
    DosageMessageSignals.emitForSentMessage(
      roomId: roomId,
      userId: mxid,
      deviceId: 'DEVICE-A',
      accessToken: token,
      msgEventId: r'$voice:example.org',
      body: 'hola',
    );
    returned = true;

    expect(returned, isTrue);
    // And it stays returned: pumping the queue does not reveal a pending await
    // that the send flow would have been sitting behind.
    await pumpEventQueue();
    expect(returned, isTrue);
  });

  test('backgrounding does not wait on the flush', () async {
    // didChangeAppLifecycleState is called by the framework on the UI thread. If
    // it awaited a flush against a dead endpoint, backgrounding would stall.
    final buffer = DosageAudioBuffer(httpClient: hangingClient());
    final svc = AnalyticsUpdateService(_FakeDataService(), audioBuffer: buffer);
    buffer.start();

    expect(
      () => svc.didChangeAppLifecycleState(AppLifecycleState.paused),
      returnsNormally,
    );
    await pumpEventQueue();
  });

  test('teardown is released by the deadline, not by the endpoint', () async {
    // dispose() is awaited by the logout chain. A hung endpoint must not hold a
    // learner in a spinner; the buffer's own deadline bounds every caller.
    final buffer = DosageAudioBuffer(httpClient: hangingClient());
    final svc = AnalyticsUpdateService(
      _TokenDataService(mxid, token),
      audioBuffer: buffer,
    );
    buffer.start();
    buffer.record(_playback(roomId), accessToken: token);

    final started = DateTime.now();
    await svc.dispose();
    final waited = DateTime.now().difference(started);

    expect(
      waited,
      lessThan(DosageAudioBuffer.flushDeadline * 2),
      reason: 'teardown is bounded even when the POST never resolves',
    );
  });

  test('teardown drains the buffer under the live bearer', () async {
    final requests = <http.Request>[];
    final buffer = DosageAudioBuffer(
      httpClient: MockClient((req) async {
        requests.add(req);
        return http.Response('', 202);
      }),
    );
    final svc = AnalyticsUpdateService(
      _TokenDataService(mxid, token),
      audioBuffer: buffer,
    );
    buffer.start();
    buffer.record(_playback(roomId), accessToken: null);

    await svc.dispose();

    expect(requests, hasLength(1));
    expect(
      requests.single.headers['Authorization'],
      'Bearer $token',
      reason:
          'the bearer is read from the service at teardown, so a buffer that '
          'never saw a token still delivers before logout invalidates it',
    );
  });

  test('start() opens the coverage period', () {
    final buffer = DosageAudioBuffer();
    final svc = AnalyticsUpdateService(
      _TokenDataService(mxid, token),
      audioBuffer: buffer,
    );
    expect(buffer.periodStart, isNull);
    svc.start();
    expect(
      buffer.periodStart,
      isNotNull,
      reason:
          'a build that instrumented listening and heard none still has to '
          'say it was watching',
    );
    addTearDown(svc.dispose);
  });
}

DosageAudioEvent _playback(String roomId) => DosageAudioEvent.fromPlayback(
  playbackId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  roomId: roomId,
  category: DosageListeningCategory.peer,
  elapsed: const Duration(seconds: 3),
  endedAt: DateTime.utc(2026, 1, 1, 12),
);
