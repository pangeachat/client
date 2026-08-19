import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/composer_keyboard_context.dart';

/// #8465 — the composer's iOS keyboard language is kept sticky per target
/// language by handing the text_input_context plugin an identifier while the
/// composer has focus, and clearing it when focus leaves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pangea/text_input_context');
  final sentIdentifiers = <String?>[];

  setUp(() {
    sentIdentifiers.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          sentIdentifiers.add((call.arguments as Map)['identifier'] as String?);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<FocusNode> pumpFocusable(WidgetTester tester, FocusNode node) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(focusNode: node, child: const SizedBox()),
      ),
    );
    return node;
  }

  /// testWidgets checks the platform override is restored before tearDowns
  /// run, so it has to be reset inside the body.
  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('identifierFor', () {
    test('keys on the target language', () {
      expect(ComposerKeyboardContext.identifierFor('es'), 'pangea.composer.es');
      expect(
        ComposerKeyboardContext.identifierFor('pt-BR'),
        'pangea.composer.pt-BR',
      );
    });

    test('is null without a target language', () {
      expect(ComposerKeyboardContext.identifierFor(null), isNull);
      expect(ComposerKeyboardContext.identifierFor(''), isNull);
    });
  });

  testWidgets('sets the identifier on focus and clears it on blur', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.iOS, () async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final context = ComposerKeyboardContext(
        focusNode: node,
        targetLanguageCode: () => 'es',
      );
      addTearDown(context.dispose);
      await pumpFocusable(tester, node);

      node.requestFocus();
      await tester.pump();
      expect(sentIdentifiers, ['pangea.composer.es']);

      node.unfocus();
      await tester.pump();
      expect(sentIdentifiers, ['pangea.composer.es', null]);
    });
  });

  testWidgets('reads the target language at focus time', (tester) async {
    await onPlatform(TargetPlatform.iOS, () async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var langCode = 'es';
      final context = ComposerKeyboardContext(
        focusNode: node,
        targetLanguageCode: () => langCode,
      );
      addTearDown(context.dispose);
      await pumpFocusable(tester, node);

      node.requestFocus();
      await tester.pump();
      node.unfocus();
      await tester.pump();

      langCode = 'fr';
      node.requestFocus();
      await tester.pump();
      expect(sentIdentifiers.last, 'pangea.composer.fr');
    });
  });

  testWidgets('notifies before listeners added later, as EditableText is', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.iOS, () async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final order = <String>[];
      final context = ComposerKeyboardContext(
        focusNode: node,
        targetLanguageCode: () {
          order.add('context');
          return 'es';
        },
      );
      addTearDown(context.dispose);
      // Stands in for EditableText, which registers when the field is built.
      node.addListener(() => order.add('editable'));
      await pumpFocusable(tester, node);

      node.requestFocus();
      await tester.pump();
      expect(order, ['context', 'editable']);
    });
  });

  testWidgets('does nothing after dispose', (tester) async {
    await onPlatform(TargetPlatform.iOS, () async {
      final node = FocusNode();
      addTearDown(node.dispose);
      ComposerKeyboardContext(
        focusNode: node,
        targetLanguageCode: () => 'es',
      ).dispose();
      await pumpFocusable(tester, node);

      node.requestFocus();
      await tester.pump();
      expect(sentIdentifiers, isEmpty);
    });
  });

  testWidgets('is silent off iOS', (tester) async {
    await onPlatform(TargetPlatform.android, () async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final context = ComposerKeyboardContext(
        focusNode: node,
        targetLanguageCode: () => 'es',
      );
      addTearDown(context.dispose);
      await pumpFocusable(tester, node);

      node.requestFocus();
      await tester.pump();
      expect(sentIdentifiers, isEmpty);
    });
  });
}
