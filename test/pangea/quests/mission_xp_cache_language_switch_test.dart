import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics/construct_use_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/analytics_update_dispatcher.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/quests/mission_xp_cache.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../analytics_data/analytics_fixtures.dart';

/// The Mission XP cache across a target-language switch (#9678). A switch
/// reaches the cache before the analytics store re-initialises for the new
/// language, and a re-init can fail; in neither case may the cache hold an
/// empty or other-language read as the new language's XP, which the meters
/// would show and the course progress record would post.
void main() {
  final fr = LanguageModel(langCode: 'fr', displayName: 'French');
  final es = LanguageModel(langCode: 'es', displayName: 'Spanish');
  final de = LanguageModel(langCode: 'de', displayName: 'German');
  final en = LanguageModel(langCode: 'en', displayName: 'English');
  late _Analytics analytics;
  late _Users users;
  final cache = MissionXpCache.instance;

  /// Lets every queued refresh run: one asked for while another is in flight
  /// runs after it, so a single await can return before the cache settles.
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await cache.refresh();
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> switchTo(LanguageModel next) async {
    final prev = users.userL2;
    users.userL2 = next;
    users.languageStream.add(
      LanguageUpdate(baseLang: en, targetLang: next, prevTargetLang: prev),
    );
    await settle();
  }

  setUpAll(() async {
    analytics = _Analytics()..loaded = 'fr';
    users = _Users()..userL2 = fr;
    MatrixState.pangeaController = _Controller(users, _Matrix(analytics));
    cache.ensureWired();
    await settle();
    expect(cache.hasReadFor('fr'), isTrue);
  });

  test('a switch waits for the store to load the new language', () async {
    // The old init has completed and the store holds no Spanish yet.
    await switchTo(es);

    expect(cache.hasReadFor('es'), isFalse);
    expect(cache.loading, isTrue);

    // The re-init loads Spanish and announces it.
    analytics
      ..store['es'] = [
        use(
          lemma: 'hola',
          useType: ConstructUseTypeEnum.wa,
          xp: 3,
          roomId: '!session',
          ts: at(0),
        ),
        use(lemma: 'ser', xp: 5, ts: at(1)),
      ]
      ..loaded = 'es';
    analytics.updateDispatcher.constructUpdateStream.add(
      AnalyticsStreamUpdate(),
    );
    await settle();

    expect(cache.hasReadFor('es'), isTrue);
    expect(cache.loading, isFalse);
    expect(cache.chatXpByRoom, {'!session': 3});
    expect(cache.practiceXpByLemma, {'ser': 5});
  });

  test('a failed re-init keeps no other language\'s read', () async {
    analytics
      ..initError = Exception('init failed')
      ..loaded = null;
    await switchTo(de);

    expect(cache.hasReadFor('de'), isFalse);
    expect(cache.loading, isFalse);
    expect(cache.chatXpByRoom, isEmpty);
    expect(cache.practiceXpByLemma, isEmpty);
  });
}

class _Analytics implements AnalyticsDataService {
  @override
  final AnalyticsUpdateDispatcher updateDispatcher = _Dispatcher();

  @override
  Completer<void> initCompleter = Completer<void>()..complete();

  @override
  Object? initError;

  @override
  bool get hasInitError => initError != null;

  /// The language the store last finished initialising for.
  String? loaded;

  @override
  String? get initializedLanguage => loaded;

  /// What the store holds, by language.
  final Map<String, List<OneConstructUse>> store = {};

  @override
  Future<List<OneConstructUse>> getUses(
    String language, {
    int? count,
    String? roomId,
    DateTime? since,
    List<ConstructUseTypeEnum>? types,
    bool filterCapped = true,
  }) async => store[language] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Dispatcher implements AnalyticsUpdateDispatcher {
  @override
  final StreamController<AnalyticsStreamUpdate> constructUpdateStream =
      StreamController<AnalyticsStreamUpdate>.broadcast();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Users implements UserController {
  @override
  LanguageModel? userL2;

  @override
  final StreamController<LanguageUpdate> languageStream =
      StreamController<LanguageUpdate>.broadcast();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Matrix implements MatrixState {
  _Matrix(this.analytics);

  final AnalyticsDataService analytics;

  @override
  AnalyticsDataService? get analyticsServiceIfExists => analytics;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_Matrix';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Controller implements PangeaController {
  _Controller(this.userController, this.matrixState);

  @override
  final UserController userController;

  @override
  final MatrixState matrixState;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
