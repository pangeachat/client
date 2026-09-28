import 'dart:async';

import 'package:fluffychat/features/user/analytics_profile_model.dart';
import 'package:fluffychat/features/user/public_profile_model.dart';
import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';
import 'package:fluffychat/routes/settings/settings_learning/tool_settings_enum.dart';

/// The smallest controller that satisfies
/// `MatrixState.isPangeaControllerInitialized` and serves a viewer L1.
///
/// Repos gate their reads on that getter (#8339), so a test that wants the repo
/// to actually reach the network path must install one of these. By default it
/// has no access token, so the fetch still fails inside `BaseRepo._fetch`'s
/// try/catch and surfaces as `Result.error` — the shape most repo tests want.
/// Pass [accessToken] to get past that and drive the real request path (against
/// a `MockClient`), which is what a test of the failure *contract* needs.
class FakePangeaController implements PangeaController {
  @override
  final UserController userController;

  /// [analyticsProfiles] serves a public analytics profile per user id — the
  /// course leaderboard ranks on these; anyone absent gets an empty profile.
  FakePangeaController({
    String? userL1Code = 'en',
    String? accessToken,
    Map<String, AnalyticsProfileModel> analyticsProfiles = const {},
  }) : userController = _FakeUserController(
         userL1Code,
         accessToken,
         analyticsProfiles,
       );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUserController implements UserController {
  _FakeUserController(
    this._userL1Code,
    this._accessToken,
    this._analyticsProfiles,
  );

  final String? _userL1Code;
  final String? _accessToken;
  final Map<String, AnalyticsProfileModel> _analyticsProfiles;

  @override
  String? get userL1Code => _userL1Code;

  /// Mirrors the real controller, which throws rather than serving a null token
  /// when nobody is logged in.
  @override
  String get accessToken =>
      _accessToken ??
      (throw "Trying to get accessToken with null token. User is not logged in.");

  /// Left uncompleted, which is what the real controller looks like before the
  /// profile lands. Callers that read it — `InstructionsEnum.isToggledOff`, for
  /// one — take their "profile not ready" branch, rather than the
  /// `Null is not a subtype of Completer` they'd get from [noSuchMethod].
  @override
  Completer<void> initCompleter = Completer<void>();

  /// Tool toggles read as off — the fresh-profile default. The message render
  /// path reads `isToolEnabled(ToolSetting.immersionMode)`
  /// ([PangeaMessageEvent.messageDisplayLangCode]), where the `noSuchMethod`
  /// null would throw `Null is not a subtype of bool`.
  @override
  bool isToolEnabled(ToolSetting setting) => false;

  /// No profile, delivered as a real future — `LevelDisplayName._fetchProfile`
  /// awaits this in initState, where the `noSuchMethod` null would throw
  /// `Null is not a subtype of Future<PublicProfileModel?>`.
  @override
  Future<PublicProfileModel?> getPublicProfile(String userId) async => null;

  /// The real controller answers an empty profile for a user with none, and
  /// the member loader stores the result, so this must never be null.
  @override
  Future<AnalyticsProfileModel> getPublicAnalyticsProfile(
    String userId,
  ) async => _analyticsProfiles[userId] ?? AnalyticsProfileModel();

  /// Languages unset — the fresh-profile default. The chat-list preview reads
  /// this (`_LastEventPreview._showPangeaContent`), where the [noSuchMethod]
  /// null would throw `Null is not a subtype of bool`.
  @override
  bool get languagesSet => false;

  /// A real, never-firing stream. Every content-language chip subscribes to
  /// this in build (`ContextLanguageSwitchTarget`), and `QuestObjectivesLoader`
  /// subscribes to it in its constructor to re-read a course outline when the
  /// display language changes (#9151) — where the [noSuchMethod] null throws
  /// before the widget can build at all.
  @override
  final StreamController<LanguageUpdate> languageStream =
      StreamController<LanguageUpdate>.broadcast();

  /// The other half of that pair, and real for the same reason: a profile
  /// write reaches exactly one of the two, and the "app in target language"
  /// toggle — which changes no language but does change the resolved display
  /// one — arrives here. Nothing emits on either unless a test does.
  @override
  final StreamController<Profile> settingsUpdateStream =
      StreamController<Profile>.broadcast();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
