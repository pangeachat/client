import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/dosage/dosage_message_signals.dart';
import 'package:fluffychat/features/dosage/dosage_signals_repo.dart';

/// The dosage emitter runs on the notification-reply path, which can execute in
/// the background isolate where dotenv / Environment are NOT loaded. Reading the
/// ship-dark gate there once threw NotInitializedError out of a fire-and-forget
/// caller; these tests pin that an unreadable environment resolves to disabled
/// and the emitter never throws.
///
/// This file deliberately never calls `dotenv.testLoad`, so dotenv stays
/// uninitialized (each test file runs in its own isolate) — mimicking the
/// background isolate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Stub path_provider so GetStorage('env_override') initializes; its read
    // then returns null, so Environment.appConfigOverride is null and the flags
    // fall through to dotenv — which is never loaded here.
    final tempDir = await Directory.systemTemp.createTemp('dosage_env_safety');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('env_override');
  });

  test('precondition: dotenv is uninitialized in this isolate', () {
    expect(dotenv.isInitialized, isFalse);
  });

  test('isEnabled resolves to false (never throws) with no environment', () {
    expect(DosageSignalsRepo.isEnabled, isFalse);
  });

  test('emitForSentMessage no-ops (never throws) with no environment', () {
    expect(
      () => DosageMessageSignals.emitForSentMessage(
        roomId: '!room:example.org',
        userId: '@user:example.org',
        deviceId: 'DEVICE-A',
        accessToken: 'syt_token',
        msgEventId: '\$evt:example.org',
        body: 'hola',
      ),
      returnsNormally,
    );
  });
}
