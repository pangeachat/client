import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keyboard_languages/keyboard_languages.dart';

import 'package:fluffychat/routes/chat/choreographer/igc/local_spell_check.dart';

/// Exercises the real platform spell checker, which no unit test can reach —
/// every other test in this feature stands in a fake for the method channel.
///
/// Run against a device or emulator:
///   fvm flutter test integration_test/local_spell_check_device_test.dart -d [device-id]
///
/// A focused text field has to be on screen: iOS routes spell check through
/// its text input plumbing and answers nothing without one.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpFocusedField(WidgetTester tester) async {
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(focusNode: focus)),
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
  }

  testWidgets('the device reports languages it can spell check', (
    tester,
  ) async {
    await pumpFocusedField(tester);

    final available = await KeyboardLanguages.getAvailableSpellCheckLanguages();
    debugPrint('available (${available.length}): $available');

    expect(
      available,
      isNotEmpty,
      reason:
          'no spell check languages reported — the local pass will never '
          'run on this device, and resolveLocale falls back to asking blind',
    );
  });

  testWidgets('a resolved locale actually returns spans', (tester) async {
    await pumpFocusedField(tester);

    final available = await KeyboardLanguages.getAvailableSpellCheckLanguages();
    final locale = LocalSpellCheck.resolveLocale('en', available);
    debugPrint('resolved en -> ${locale?.toLanguageTag()}');
    expect(locale, isNotNull);

    final spans = await LocalSpellCheck.spans(
      'I have a speling mistake',
      locale!,
    );
    debugPrint('spans: ${spans.map((s) => s.errorSpan).toList()}');

    // The whole point of resolveLocale: iOS answers nothing for a tag outside
    // its own list, so an unresolved bare code silently checks nothing.
    expect(
      spans,
      isNotEmpty,
      reason:
          'resolved locale ${locale.toLanguageTag()} found no misspelling '
          'in text that clearly contains one',
    );
  });

  testWidgets('REPORT: coverage of the languages this app teaches', (
    tester,
  ) async {
    await pumpFocusedField(tester);
    final available = await KeyboardLanguages.getAvailableSpellCheckLanguages();

    for (final code in [
      'en',
      'es',
      'fr',
      'de',
      'it',
      'pt',
      'ca',
      'ja',
      'ko',
      'zh',
      'ru',
      'vi',
    ]) {
      final locale = LocalSpellCheck.resolveLocale(code, available);
      debugPrint('$code -> ${locale?.toLanguageTag() ?? "NO DICTIONARY"}');
    }
  });
}
