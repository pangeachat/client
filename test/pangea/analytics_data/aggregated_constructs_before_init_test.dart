import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_database.dart';
import '../get_test_client.dart';

/// Regression: Sentry CLIENT-D44 (#9284).
///
/// The Vocab and Grammar panels load their lists through
/// getAggregatedConstructs as soon as they open. It read the store without
/// waiting for init, so a panel opened right after sign-in hit a null check
/// and its spinner never cleared. Like every other read, it must wait.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('aggregated');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => tempDir.path,
        );
    await GetStorage.init('env_override');
    dotenv.testLoad(
      mergeWith: {
        'BOT_NAME': 'pangeabot',
        'ANALYTICS_DUAL_WRITE_ENABLED': 'true',
        'DOSAGE_SIGNALS_ENABLED': 'true',
        'TEACHER_BFF_API': 'https://bff.test.example',
      },
    );
  });

  test('getAggregatedConstructs waits for init instead of reading a store '
      'that has not opened', () async {
    final client = await getTestClient();
    addTearDown(client.dispose);

    // A store that never opens, so init never completes.
    final service = AnalyticsDataService(
      client,
      databaseBuilder: (_) => Completer<AnalyticsDatabase>().future,
    );
    expect(
      service.isInitializing,
      isTrue,
      reason: 'precondition: analytics init has not completed',
    );

    Object? error;
    var done = false;
    service
        .getAggregatedConstructs(ConstructTypeEnum.vocab, 'es')
        .then((_) => done = true, onError: (Object e) => error = e);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(error, isNull);
    expect(done, isFalse, reason: 'the read must wait for init');
  });
}
