import 'package:fluffychat/features/user/user_controller.dart';
import 'package:fluffychat/pangea/common/controllers/pangea_controller.dart';

/// The smallest controller that satisfies
/// `MatrixState.isPangeaControllerInitialized` and serves a viewer L1.
///
/// Repos gate their reads on that getter (#8339), so a test that wants the repo
/// to actually reach the network path must install one of these. It has no
/// access token, so the fetch still fails inside `BaseRepo._fetch`'s try/catch
/// and surfaces as `Result.error` — the shape most repo tests want.
class FakePangeaController implements PangeaController {
  @override
  final UserController userController;

  FakePangeaController({String? userL1Code = 'en'})
    : userController = _FakeUserController(userL1Code);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUserController implements UserController {
  _FakeUserController(this._userL1Code);

  final String? _userL1Code;

  @override
  String? get userL1Code => _userL1Code;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
