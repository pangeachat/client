import 'dart:async';

import 'package:fluffychat/features/user/user_controller.dart';
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

  FakePangeaController({String? userL1Code = 'en', String? accessToken})
    : userController = _FakeUserController(userL1Code, accessToken);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUserController implements UserController {
  _FakeUserController(this._userL1Code, this._accessToken);

  final String? _userL1Code;
  final String? _accessToken;

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

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
