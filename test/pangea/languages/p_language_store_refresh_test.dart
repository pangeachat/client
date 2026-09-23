import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/p_language_store.dart';

Map<String, String> _language(String code) => {
  'language_code': code,
  'language_name': code,
  'l2_support': 'full',
};

void _seedCache(List<String> codes, {required DateTime fetchedAt}) =>
    SharedPreferences.setMockInitialValues({
      PrefKey.lastFetched: fetchedAt.toIso8601String(),
      PrefKey.languagesKey: jsonEncode({
        PrefKey.languagesKey: [for (final code in codes) _language(code)],
      }),
    });

/// A CMS that counts its requests and answers once [release] completes.
class _Cms {
  final release = Completer<void>();
  int requests = 0;

  late final client = MockClient((request) async {
    requests++;
    await release.future;
    return http.Response(
      jsonEncode({
        'docs': [_language('zz-cms')],
      }),
      200,
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => dotenv.testLoad(mergeWith: {'CMS_API': 'https://cms.test'}));

  final stale = DateTime.now().subtract(const Duration(days: 2));

  test(
    'a stale cache is served at once and refreshed in the background',
    () async {
      _seedCache(['zz-cached'], fetchedAt: stale);
      final cms = _Cms();

      await http.runWithClient(
        () => Future.wait([
          // PangeaController's PLanguageStore() starts a second initialize; the
          // two must share one fetch. Neither may wait for it: it is still held
          // open here.
          PLanguageStore.initialize(),
          PLanguageStore.initialize(),
        ]).timeout(const Duration(seconds: 2)),
        () => cms.client,
      );

      expect(PLanguageStore.byLangCode('zz-cached'), isNotNull);
      expect(PLanguageStore.byLangCode('zz-cms'), isNull);

      cms.release.complete();
      await pumpEventQueue();

      expect(cms.requests, 1);
      expect(PLanguageStore.byLangCode('zz-cms'), isNotNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        DateTime.parse(prefs.getString(PrefKey.lastFetched)!).isAfter(stale),
        isTrue,
      );
    },
  );

  test('a failed background refresh keeps the cache', () async {
    _seedCache(['zz-cached'], fetchedAt: stale);

    await http.runWithClient(
      PLanguageStore.initialize,
      () => MockClient((_) async => http.Response('', 500)),
    );
    await pumpEventQueue();

    expect(PLanguageStore.byLangCode('zz-cached'), isNotNull);
    // 'ab' is in the hardcoded fallback list, so it would appear had the
    // failure replaced the cache.
    expect(PLanguageStore.byLangCode('ab'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefKey.lastFetched), stale.toIso8601String());
  });

  test('with no cache, startup waits for the CMS list', () async {
    SharedPreferences.setMockInitialValues({});
    final cms = _Cms()..release.complete();

    await http.runWithClient(PLanguageStore.initialize, () => cms.client);

    expect(cms.requests, 1);
    expect(PLanguageStore.byLangCode('zz-cms'), isNotNull);
  });

  test('a fresh cache makes no request', () async {
    _seedCache(['zz-cached'], fetchedAt: DateTime.now());
    final cms = _Cms()..release.complete();

    await http.runWithClient(PLanguageStore.initialize, () => cms.client);

    expect(cms.requests, 0);
    expect(PLanguageStore.byLangCode('zz-cached'), isNotNull);
  });
}
