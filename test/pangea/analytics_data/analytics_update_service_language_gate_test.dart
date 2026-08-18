import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_service.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'analytics_fixtures.dart';

/// #7720 — a construct use tagged with a language other than the current L2
/// must never enter the analytics pipeline.
///
/// The local database is partitioned by the L2's short code; only that
/// partition is uploaded to the analytics room and only that partition seeds
/// the merge table on reinitialize. The in-memory counts the world cluster
/// reads (`numConstructs`) are NOT partitioned, so a use recorded under any
/// other key (a voice message whose STT came back labelled as the learner's
/// L1) inflated the vocab count until the next language change or restart,
/// then vanished — "366 → 365, and changing the L1 back does not bring it
/// back". `AnalyticsUpdateService.addAnalytics` is the one write entry every
/// feature uses, so the gate is proven there.
void main() {
  const l2 = 'fr';

  late _RecordingDataService dataService;
  late AnalyticsUpdateService service;

  setUpAll(() {
    MatrixState.pangeaController = _FakePangeaController(l2: l2);
  });

  setUp(() {
    dataService = _RecordingDataService();
    service = AnalyticsUpdateService(dataService);
  });

  test(
    'a use tagged with the current L2 is recorded under that language',
    () async {
      await service.addAnalytics(null, usesFor('bonjour', count: 1), l2);
      expect(dataService.dispatcher.recordedLanguages, [l2]);
    },
  );

  test(
    'a use tagged with any other language is dropped, not recorded',
    () async {
      // The learner's L1 — what STT labels an English utterance from a French
      // learner. Before the gate this reached the merge table (counted) and a
      // never-uploaded 'en' partition.
      await service.addAnalytics(null, usesFor('hello', count: 1), 'en');
      // A full code is not the partition key either.
      await service.addAnalytics(null, usesFor('salut', count: 1), 'fr-CA');
      expect(dataService.dispatcher.recordedLanguages, isEmpty);
    },
  );

  test('recordsLanguage names the L2 partition key exactly', () {
    expect(service.recordsLanguage(l2), isTrue);
    expect(service.recordsLanguage('en'), isFalse);
    expect(service.recordsLanguage('fr-CA'), isFalse);
  });
}

class _RecordingDispatcher implements AnalyticsUpdateDispatcher {
  final List<String> recordedLanguages = [];

  @override
  Future<void> sendLocalAnalyticsUpdate(
    AnalyticsUpdate analyticsUpdate,
    String language,
  ) async {
    recordedLanguages.add(language);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Only what `addAnalytics` touches after the gate: the dispatch, then the
/// two reads that decide whether to flush now (answered "nothing pending").
class _RecordingDataService implements AnalyticsDataService {
  final _RecordingDispatcher dispatcher = _RecordingDispatcher();

  @override
  AnalyticsUpdateDispatcher get updateDispatcher => dispatcher;

  @override
  Future<int> getLocalConstructCount(String language) async => 0;

  @override
  Future<DateTime?> getLastUpdatedAnalytics(String language) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePangeaController implements PangeaController {
  @override
  final UserController userController;

  _FakePangeaController({required String l2})
    : userController = _FakeUserController(l2);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUserController implements UserController {
  _FakeUserController(this._l2);

  final String _l2;

  @override
  LanguageModel? get userL2 => LanguageModel(langCode: _l2, displayName: _l2);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
