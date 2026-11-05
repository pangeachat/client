import 'package:flutter/material.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/routes/chat/pangea_emoji_search_view.dart';

/// #9412 — the chat's emoji search matches keywords in the app's language and
/// in the learner's target language (L2), and follows a change of either.
void main() {
  LanguageModel language(String code) =>
      LanguageModel(langCode: code, displayName: code);

  EmojiViewState pickerState(String appLanguage) => EmojiViewState(
    getDefaultEmojiLocale(Locale(appLanguage)),
    (category, emoji) {},
    null,
    () {},
    () {},
    null,
  );

  Future<void> pumpSearchView(
    WidgetTester tester, {
    required ValueNotifier<EmojiViewState> state,
    required ValueNotifier<LanguageModel?> targetLanguage,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([state, targetLanguage]),
            builder: (context, _) => PangeaEmojiSearchView(
              const Config(),
              state.value,
              () {},
              targetLanguage: targetLanguage.value,
            ),
          ),
        ),
      ),
    );
    // Let the view's initial load of recent emojis finish before searching.
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('finds an emoji by its target-language keyword', (tester) async {
    await pumpSearchView(
      tester,
      state: ValueNotifier(pickerState('en')),
      targetLanguage: ValueNotifier(language('ru')),
    );

    await search(tester, 'кот');

    expect(find.text('🐱'), findsOneWidget);
  });

  testWidgets('still finds an emoji by its app-language keyword', (
    tester,
  ) async {
    await pumpSearchView(
      tester,
      state: ValueNotifier(pickerState('en')),
      targetLanguage: ValueNotifier(language('ru')),
    );

    await search(tester, 'cat');

    expect(find.text('🐱'), findsOneWidget);
  });

  testWidgets('lists an emoji once when both languages match it', (
    tester,
  ) async {
    await pumpSearchView(
      tester,
      state: ValueNotifier(pickerState('en')),
      targetLanguage: ValueNotifier(language('es')),
    );

    await search(tester, 'pizza');

    expect(find.text('🍕'), findsOneWidget);
  });

  testWidgets('lists an emoji the picker files under two categories once', (
    tester,
  ) async {
    await pumpSearchView(
      tester,
      state: ValueNotifier(pickerState('en')),
      targetLanguage: ValueNotifier(null),
    );

    await search(tester, 'luggage');

    expect(find.text('🧳'), findsOneWidget);
  });

  testWidgets('a regional target language uses its language\'s keywords', (
    tester,
  ) async {
    await pumpSearchView(
      tester,
      state: ValueNotifier(pickerState('en')),
      targetLanguage: ValueNotifier(language('es-MX')),
    );

    await search(tester, 'gato');

    expect(find.text('🐱'), findsOneWidget);
  });

  testWidgets('a target language the picker has no keywords in adds none', (
    tester,
  ) async {
    await pumpSearchView(
      tester,
      state: ValueNotifier(pickerState('es')),
      targetLanguage: ValueNotifier(language('ko')),
    );

    await search(tester, 'gato');
    expect(find.text('🐱'), findsOneWidget);

    await search(tester, 'cat');
    expect(find.text('🐱'), findsNothing);
  });

  testWidgets('a change of target language reaches search', (tester) async {
    final targetLanguage = ValueNotifier<LanguageModel?>(language('ru'));
    await pumpSearchView(
      tester,
      state: ValueNotifier(pickerState('en')),
      targetLanguage: targetLanguage,
    );
    await search(tester, 'кот');
    expect(find.text('🐱'), findsOneWidget);

    targetLanguage.value = language('es');
    await tester.pump();

    await search(tester, 'gato');
    expect(find.text('🐱'), findsOneWidget);
    await search(tester, 'кот');
    expect(find.text('🐱'), findsNothing);
  });

  testWidgets('a change of app language reaches search', (tester) async {
    final state = ValueNotifier(pickerState('en'));
    await pumpSearchView(
      tester,
      state: state,
      targetLanguage: ValueNotifier(null),
    );
    await search(tester, 'cat');
    expect(find.text('🐱'), findsOneWidget);

    state.value = pickerState('es');
    await tester.pump();

    await search(tester, 'gato');
    expect(find.text('🐱'), findsOneWidget);
  });
}
