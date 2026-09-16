import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/screen_size_warning_dialog.dart';

/// #8179: the "expand your screen size" warning must react to the window the
/// user could actually resize. It has to read that height live — not from a
/// `MediaQuery` that only refreshes on the next frame, which made it react one
/// resize late — and it has to ignore an on-screen keyboard, whether the
/// keyboard is reported as a bottom view inset (mobile web) or as a genuinely
/// smaller window (a keyboard docked into the OS work area). It must also never
/// take focus: stealing focus from the composer blurs the browser's input,
/// which closes a focus-following on-screen keyboard the moment it opens.
void main() {
  /// Logical pixels == physical pixels, and undo the size overrides afterwards.
  void useTestView(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
  }

  /// Pumps an app and returns a context under its navigator, the way
  /// `MatrixState` hands the router's navigator context to the warning.
  Future<BuildContext> pumpApp(WidgetTester tester, {Widget? home}) async {
    late BuildContext navigatorContext;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            navigatorContext = context;
            return Scaffold(body: home);
          },
        ),
      ),
    );
    // L10n is deferred-loaded, so the subtree only builds once it resolves.
    await tester.pumpAndSettle();
    return navigatorContext;
  }

  /// A short window with plenty of work area left to expand into.
  void shrink(ScreenSizeWarning warning, BuildContext context) =>
      warning.onWindowMetrics(
        height: 400,
        growableHeight: 500,
        navigatorContext: context,
      );

  final warningFinder = find.byType(ScreenSizeWarningDialog);

  testWidgets('warns on a too-short window', (tester) async {
    useTestView(tester);
    final context = await pumpApp(tester);

    shrink(ScreenSizeWarning(), context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsOneWidget);
  });

  testWidgets('closes itself once the window is tall enough again', (
    tester,
  ) async {
    useTestView(tester);
    final context = await pumpApp(tester);
    final warning = ScreenSizeWarning();

    shrink(warning, context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsOneWidget);

    warning.onWindowMetrics(
      height: 900,
      growableHeight: 0,
      navigatorContext: context,
    );
    await tester.pumpAndSettle();
    expect(warningFinder, findsNothing);
    expect(warning.isShowing, isFalse);
  });

  testWidgets('stays up while the window is still too short', (tester) async {
    useTestView(tester);
    final context = await pumpApp(tester);
    final warning = ScreenSizeWarning();

    shrink(warning, context);
    await tester.pumpAndSettle();

    warning.onWindowMetrics(
      height: 300,
      growableHeight: 600,
      navigatorContext: context,
    );
    await tester.pumpAndSettle();
    expect(warningFinder, findsOneWidget);
  });

  testWidgets('does not warn again until the window has grown back', (
    tester,
  ) async {
    useTestView(tester);
    final context = await pumpApp(tester);
    final warning = ScreenSizeWarning();

    shrink(warning, context);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(warningFinder, findsNothing);
    expect(warning.isShowing, isFalse);

    // Still short: the user has been told, don't nag on every resize.
    warning.onWindowMetrics(
      height: 420,
      growableHeight: 480,
      navigatorContext: context,
    );
    await tester.pumpAndSettle();
    expect(warningFinder, findsNothing);

    // Grown back and shrunk again: that's a new occasion to warn.
    warning.onWindowMetrics(
      height: 900,
      growableHeight: 0,
      navigatorContext: context,
    );
    shrink(warning, context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsOneWidget);
  });

  testWidgets('does not warn when the window already fills the work area', (
    tester,
  ) async {
    useTestView(tester);
    final context = await pumpApp(tester);
    final warning = ScreenSizeWarning();

    // Short, but there is no taller window to expand to: a docked on-screen
    // keyboard shrank the OS work area (and the maximized browser with it), or
    // the browser fills a small display. Asking to expand would be noise —
    // and on keyboard close the window grows back on its own (#8179).
    warning.onWindowMetrics(
      height: 400,
      growableHeight: 0,
      navigatorContext: context,
    );
    await tester.pumpAndSettle();
    expect(warningFinder, findsNothing);

    warning.onWindowMetrics(
      height: 400,
      growableHeight: kMinGrowableHeight - 1,
      navigatorContext: context,
    );
    await tester.pumpAndSettle();
    expect(warningFinder, findsNothing);
  });

  testWidgets('comes down when the window stops being expandable', (
    tester,
  ) async {
    useTestView(tester);
    final context = await pumpApp(tester);
    final warning = ScreenSizeWarning();

    shrink(warning, context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsOneWidget);

    // A keyboard docks while the warning is up: the window now fills what is
    // left of the work area, so there is nothing to ask for anymore.
    warning.onWindowMetrics(
      height: 300,
      growableHeight: 0,
      navigatorContext: context,
    );
    await tester.pumpAndSettle();
    expect(warningFinder, findsNothing);
  });

  testWidgets('does not steal focus from a text field', (tester) async {
    useTestView(tester);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final context = await pumpApp(
      tester,
      home: TextField(focusNode: focusNode, autofocus: true),
    );
    await tester.pumpAndSettle();
    expect(focusNode.hasPrimaryFocus, isTrue);

    // The reopen of #8179: showing the warning as a dialog route moved focus
    // off the composer, which blurred the browser's input and closed the
    // user's on-screen keyboard the moment it opened.
    shrink(ScreenSizeWarning(), context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsOneWidget);
    expect(focusNode.hasPrimaryFocus, isTrue);
  });

  testWidgets('the app behind the warning stays interactive', (tester) async {
    useTestView(tester);
    var pressed = false;
    final context = await pumpApp(
      tester,
      home: Align(
        alignment: Alignment.topLeft,
        child: TextButton(
          onPressed: () => pressed = true,
          child: const Text('behind'),
        ),
      ),
    );

    shrink(ScreenSizeWarning(), context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsOneWidget);

    // No modal barrier: the user can keep typing (or fixing their window)
    // with the warning up.
    await tester.tap(find.text('behind'));
    expect(pressed, isTrue);
  });

  testWidgets('an on-screen keyboard does not shorten the window', (
    tester,
  ) async {
    useTestView(tester);
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );

    tester.view.physicalSize = const Size(800, 400);
    expect(screenIsTooShort(context), isTrue);

    // Same window, now with a keyboard covering the bottom 300px: the window
    // itself hasn't changed, so there is nothing for the user to expand.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    expect(windowHeight(context), 700);
    expect(screenIsTooShort(context), isFalse);
  });

  testWidgets('window height is current inside didChangeMetrics', (
    tester,
  ) async {
    useTestView(tester);
    tester.view.physicalSize = const Size(800, 900);

    final observer = _HeightObserver();
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          observer.context = context;
          return const SizedBox();
        },
      ),
    );
    WidgetsBinding.instance.addObserver(observer);
    addTearDown(() => WidgetsBinding.instance.removeObserver(observer));

    tester.view.physicalSize = const Size(800, 400);

    // Measured during the metrics callback, before any frame is built: the
    // height must already be the new one, not the one we resized away from.
    expect(observer.heights.last, 400);
  });
}

/// Records the window height as measured from inside [didChangeMetrics].
class _HeightObserver with WidgetsBindingObserver {
  late BuildContext context;
  final List<double> heights = [];

  @override
  void didChangeMetrics() => heights.add(windowHeight(context));
}
