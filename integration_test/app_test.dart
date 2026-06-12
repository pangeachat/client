import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Integration Test', () {
    setUpAll(() async {
      // this random dialog popping up is super hard to cover in tests
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });
    });
  });
}
