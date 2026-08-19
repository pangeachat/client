import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/chat/composer_keyboard_context.dart';

/// Stands in for EditableText: registers a FocusNode listener in initState,
/// i.e. after the wrapping ComposerKeyboardContext registered its own.
class _FocusListenerChild extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onFocusChanged;

  const _FocusListenerChild({
    required this.focusNode,
    required this.onFocusChanged,
  });

  @override
  State<_FocusListenerChild> createState() => _FocusListenerChildState();
}

class _FocusListenerChildState extends State<_FocusListenerChild> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(widget.onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(widget.onFocusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: widget.focusNode, child: const SizedBox());
}

/// #8465 — the composer's iOS keyboard language is kept sticky per target
/// language by handing the text_input_context plugin an identifier while the
/// composer has focus, and clearing it when focus leaves or the composer is
/// unmounted.
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

  Future<void> pumpComposer(
    WidgetTester tester,
    FocusNode node, {
    String? Function()? targetLanguageCode,
    VoidCallback? childFocusListener,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComposerKeyboardContext(
          focusNode: node,
          targetLanguageCode: targetLanguageCode ?? () => 'es',
          child: _FocusListenerChild(
            focusNode: node,
            onFocusChanged: childFocusListener ?? () {},
          ),
        ),
      ),
    );
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
      await pumpComposer(tester, node);

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
      await pumpComposer(tester, node, targetLanguageCode: () => langCode);

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

  testWidgets('notifies before the child\'s listener, as EditableText is', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.iOS, () async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final order = <String>[];
      await pumpComposer(
        tester,
        node,
        targetLanguageCode: () {
          order.add('context');
          return 'es';
        },
        childFocusListener: () => order.add('editable'),
      );

      node.requestFocus();
      await tester.pump();
      expect(order, ['context', 'editable']);
    });
  });

  // A FocusNode detached while focused never notifies its listeners, so the
  // widget's dispose is the only chance to clear the identifier before the
  // next field attaches — otherwise that field inherits it (the #8465
  // "switching elsewhere resets the composer" report).
  testWidgets('clears the identifier when unmounted while focused', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.iOS, () async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpComposer(tester, node);

      node.requestFocus();
      await tester.pump();
      expect(sentIdentifiers, ['pangea.composer.es']);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(sentIdentifiers, ['pangea.composer.es', null]);
    });
  });

  testWidgets('is silent off iOS', (tester) async {
    await onPlatform(TargetPlatform.android, () async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpComposer(tester, node);

      node.requestFocus();
      await tester.pump();
      node.unfocus();
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(sentIdentifiers, isEmpty);
    });
  });
}
