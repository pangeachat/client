import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/features/activity_sessions/activity_rating_store.dart';

/// The rated-store drives the post-play prompt's "don't reappear after
/// submit" rule, per pinned version: a session pinned to a DIFFERENT version
/// of an already-rated activity re-prompts (re-prompt-and-overwrite, #7194).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // GetStorage needs path_provider; stub the channel to a temp dir.
    final tempDir = await Directory.systemTemp.createTemp('rating_store_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
  });

  setUp(() async {
    await GetStorage.init(ActivityRatingStore.storageKey);
    await GetStorage(ActivityRatingStore.storageKey).erase();
  });

  test('unrated activity reports false', () {
    expect(ActivityRatingStore.hasRated('a1', 'v1'), isFalse);
  });

  test('rated activity reports true for the same version', () async {
    await ActivityRatingStore.markRated('a1', 'v1');
    expect(ActivityRatingStore.hasRated('a1', 'v1'), isTrue);
  });

  test('a different pinned version re-prompts', () async {
    await ActivityRatingStore.markRated('a1', 'v1');
    expect(ActivityRatingStore.hasRated('a1', 'v2'), isFalse);
  });

  test(
    'null version (legacy room) matches only a null-version rating',
    () async {
      await ActivityRatingStore.markRated('a1', null);
      expect(ActivityRatingStore.hasRated('a1', null), isTrue);
      expect(ActivityRatingStore.hasRated('a1', 'v1'), isFalse);
    },
  );

  test('activities are independent', () async {
    await ActivityRatingStore.markRated('a1', 'v1');
    expect(ActivityRatingStore.hasRated('a2', 'v1'), isFalse);
  });
}
