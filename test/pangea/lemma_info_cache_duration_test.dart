import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/utils/repo_cache_item.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_repo.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_request.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'fake_pangea_controller.dart';

/// Vocab search matches against the meanings already on disk without
/// fetching (#9042), so a loaded meaning has to outlive the session that
/// loaded it. It used to expire after 10 minutes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('lemma_cache');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async => tempDir.path,
        );
    await GetStorage.init('lemma_storage');
    MatrixState.pangeaController = FakePangeaController();
    await LemmaInfoRepo.instance.cacheReady;
  });

  final meaning = LemmaInfoResponse(emoji: const ['👋'], meaning: 'hello');

  var seq = 0;
  LemmaInfoRequest lemmaRequest() => LemmaInfoRequest(
    lemma: 'bonjour${seq++}',
    partOfSpeech: 'intj',
    lemmaLang: 'fr',
    userL1: 'en',
    messageInfo: const {},
  );

  Future<LemmaInfoRequest> cachedAgo(Duration age) async {
    final request = lemmaRequest();
    await LemmaInfoRepo.instance.cache.set(
      request.storageKey,
      RepoCacheItem(timestamp: DateTime.now().subtract(age), response: meaning),
    );
    return request;
  }

  test('a meaning loaded 29 days ago is still served from disk', () async {
    final request = await cachedAgo(const Duration(days: 29));
    expect(LemmaInfoRepo.instance.getCached(request), meaning);
  });

  test('a meaning loaded 31 days ago has expired', () async {
    final request = await cachedAgo(const Duration(days: 31));
    expect(LemmaInfoRepo.instance.getCached(request), isNull);
  });
}
