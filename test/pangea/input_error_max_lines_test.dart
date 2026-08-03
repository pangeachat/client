import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';

void main() {
  const longError =
      'Your session has expired. Please log in again to change your password.';
  const shortError = 'Wrong.';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  Future<void> pumpField(WidgetTester tester, String errorText) =>
      tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Theme(
              data: FluffyThemes.buildTheme(context, Brightness.light),
              child: Scaffold(
                body: SizedBox(
                  width: 200,
                  child: TextField(
                    decoration: InputDecoration(errorText: errorText),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('field error text is allowed several lines', (tester) async {
    await pumpField(tester, longError);

    expect(AppConfig.inputErrorMaxLines, greaterThan(1));
    expect(
      tester.widget<Text>(find.text(longError)).maxLines,
      AppConfig.inputErrorMaxLines,
    );
  });

  testWidgets('a sentence-length error wraps on a narrow field', (
    tester,
  ) async {
    await pumpField(tester, shortError);
    final singleLineHeight = tester.getSize(find.text(shortError)).height;

    await pumpField(tester, longError);
    final wrappedHeight = tester.getSize(find.text(longError)).height;

    expect(wrappedHeight, greaterThan(singleLineHeight));
  });
}
