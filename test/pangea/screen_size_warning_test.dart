import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/screen_size_warning_dialog.dart';

/// #8179: the "expand your screen size" warning must react to the window the
/// user could actually resize. It has to read that height live — not from a
/// `MediaQuery` that only refreshes on the next frame, which made it react one
/// resize late — and it has to ignore a mobile on-screen keyboard, which is
/// reported as a bottom view inset rather than as a shorter window.
void main() {
  /// Logical pixels == physical pixels, and undo the size overrides afterwards.
  void useTestView(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
  }

  /// Pumps an app and returns a context under its navigator, the way
  /// `MatrixState` hands the router's navigator context to the warning.
  Future<BuildContext> pumpApp(WidgetTester tester) async {
    late BuildContext navigatorContext;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            navigatorContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    // L10n is deferred-loaded, so the subtree only builds once it resolves.
    await tester.pumpAndSettle();
    return navigatorContext;
  }

  final warningFinder = find.byType(ScreenSizeWarningDialog);

  testWidgets('warns on a too-short window', (tester) async {
    useTestView(tester);
    final context = await pumpApp(tester);

    ScreenSizeWarning().onWindowHeight(400, context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsOneWidget);
  });

  testWidgets('closes itself once the window is tall enough again', (
    tester,
  ) async {
    useTestView(tester);
    final context = await pumpApp(tester);
    final warning = ScreenSizeWarning();

    warning.onWindowHeight(400, context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsOneWidget);

    warning.onWindowHeight(900, context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsNothing);
    expect(warning.isShowing, isFalse);
  });

  testWidgets('stays up while the window is still too short', (tester) async {
    useTestView(tester);
    final context = await pumpApp(tester);
    final warning = ScreenSizeWarning();

    warning.onWindowHeight(400, context);
    await tester.pumpAndSettle();

    warning.onWindowHeight(300, context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsOneWidget);
  });

  testWidgets('does not warn again until the window has grown back', (
    tester,
  ) async {
    useTestView(tester);
    final context = await pumpApp(tester);
    final warning = ScreenSizeWarning();

    warning.onWindowHeight(400, context);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(warningFinder, findsNothing);

    // Still short: the user has been told, don't nag on every resize.
    warning.onWindowHeight(420, context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsNothing);

    // Grown back and shrunk again: that's a new occasion to warn.
    warning.onWindowHeight(900, context);
    warning.onWindowHeight(400, context);
    await tester.pumpAndSettle();
    expect(warningFinder, findsOneWidget);
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
