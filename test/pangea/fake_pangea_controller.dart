import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';

/// The smallest controller that satisfies
/// `MatrixState.isPangeaControllerInitialized` and serves a viewer L1.
///
/// Repos gate their reads on that getter (#8339), so a test that wants the repo
/// to actually reach the network path must install one of these. By default it
/// has no access token, so the fetch still fails inside `BaseRepo._fetch`'s
/// try/catch and surfaces as `Result.error` — the shape most repo tests want.
/// Pass [accessToken] when the test needs the request to be built and answered
/// by an `http` MockClient instead.
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

  /// Mirrors the real getter: non-nullable, and throws when the user is not
  /// logged in — which is what makes the token-less default fail the fetch.
  @override
  String get accessToken =>
      _accessToken ??
      (throw "Trying to get accessToken with null token. User is not logged in.");

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
