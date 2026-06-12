import 'package:fluffychat/widgets/matrix.dart';
import '../../features/user/user_model.dart' show Profile;

abstract class AccountUpdater {
  Future<void> updateProfile(Profile Function(Profile) update);
}

class UserAccountUpdater implements AccountUpdater {
  @override
  Future<void> updateProfile(Profile Function(Profile) update) => MatrixState
      .pangeaController
      .userController
      .updateProfile(update, waitForDataInSync: true);
}

class MockAccountUpdater implements AccountUpdater {
  @override
  Future<void> updateProfile(Profile Function(Profile) update) async {}
}
