import 'dart:async';

import 'package:flutter/material.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/connection_status/connection_status_controller.dart';
import 'package:fluffychat/features/connection_status/filtered_network_controller.dart';
import 'package:fluffychat/features/connection_status/network_host_category.dart';
import 'package:fluffychat/features/connection_status/widgets/connection_banner.dart';
import 'package:fluffychat/features/connection_status/widgets/filtered_network_dialog.dart';
import 'package:fluffychat/features/connection_status/widgets/filtered_network_note.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/lemmas/lemma.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_repo.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_holder.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_type_enum.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';

/// #9434, #9512 — what the user sees when the network blocks a host or the
/// connection is lost.
void main() {
  final blocked = FilteredNetworkController.instance.blocked;
  const bannerText = 'This network is blocking Pangea Chat';

  final status = ConnectionStatusController.instance.status;
  const offlineText =
      "You're offline. Pangea Chat will reconnect when your connection is back.";
  const unreachableText = "Can't reach Pangea Chat. Trying again…";

  late StreamController<List<ConnectivityResult>> networkChanges;

  setUp(() {
    // The banner watches the device's own report from the moment it is on
    // screen; a test must never reach the real plugin.
    networkChanges = StreamController.broadcast();
    ConnectionStatusController.instance.onNetworkChanged = () =>
        networkChanges.stream;
  });

  tearDown(() {
    FilteredNetworkController.instance.resetForTest();
    ConnectionStatusController.instance.resetForTest();
    unawaited(networkChanges.close());
  });

  Widget app(Widget home) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    builder: (context, child) => ConnectionBanner(child: child),
    home: Scaffold(body: home),
  );

  Future<void> setStatus(WidgetTester tester, ConnectionStatus value) async {
    status.value = value;
    await tester.pump();
  }

  Future<void> block(
    WidgetTester tester,
    Set<NetworkHostCategory> categories,
  ) async {
    blocked.value = categories;
    await tester.pump();
  }

  group('the banner', () {
    testWidgets('shows when the chat server or the Pangea API is blocked', (
      tester,
    ) async {
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      expect(find.text(bannerText), findsNothing);

      await block(tester, {NetworkHostCategory.pangeaApi});
      expect(find.text(bannerText), findsOneWidget);
    });

    testWidgets('steps aside while the guidance it opens is showing', (
      tester,
    ) async {
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      await block(tester, {NetworkHostCategory.chatServer});

      FilteredNetworkDialog.isShowing.value = true;
      await tester.pump();
      expect(find.text(bannerText), findsNothing);

      FilteredNetworkDialog.isShowing.value = false;
      await tester.pump();
      expect(find.text(bannerText), findsOneWidget);
    });

    testWidgets('does not show for a block that breaks one feature', (
      tester,
    ) async {
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      await block(tester, {NetworkHostCategory.video, NetworkHostCategory.map});

      expect(find.text(bannerText), findsNothing);
    });

    testWidgets(
      'once dismissed, comes back only when another host is blocked',
      (tester) async {
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await block(tester, {NetworkHostCategory.chatServer});
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pump();
        expect(find.text(bannerText), findsNothing);

        await block(tester, {
          NetworkHostCategory.chatServer,
          NetworkHostCategory.video,
        });
        expect(find.text(bannerText), findsNothing);

        await block(tester, {
          NetworkHostCategory.chatServer,
          NetworkHostCategory.pangeaApi,
        });
        expect(find.text(bannerText), findsOneWidget);
      },
    );

    testWidgets(
      'once dismissed, comes back after the block clears and returns',
      (tester) async {
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await block(tester, {NetworkHostCategory.chatServer});
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pump();

        await block(tester, {});
        await block(tester, {NetworkHostCategory.chatServer});
        expect(find.text(bannerText), findsOneWidget);
      },
    );
  });

  group('the connection banner', () {
    // No account is signed in, so only the device's own report can show it.
    testWidgets('before sign-in, shows the device\'s own report', (
      tester,
    ) async {
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      expect(find.text(offlineText), findsNothing);

      networkChanges.add([ConnectivityResult.none]);
      await tester.pump();
      await tester.pump();
      expect(find.text(offlineText), findsOneWidget);

      networkChanges.add([ConnectivityResult.wifi]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Back online'), findsOneWidget);

      await tester.pump(ConnectionStatusController.backOnlineFor);
      expect(find.text('Back online'), findsNothing);
    });

    testWidgets('says which way the connection is lost', (tester) async {
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      expect(find.text(offlineText), findsNothing);

      await setStatus(tester, ConnectionStatus.offline);
      expect(find.text(offlineText), findsOneWidget);

      await setStatus(tester, ConnectionStatus.unreachable);
      expect(find.text(unreachableText), findsOneWidget);
      expect(find.text(offlineText), findsNothing);

      await setStatus(tester, ConnectionStatus.backOnline);
      expect(find.text('Back online'), findsOneWidget);

      await setStatus(tester, ConnectionStatus.connected);
      expect(find.text('Back online'), findsNothing);
    });

    testWidgets('steps aside for the filtered-network banner', (tester) async {
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      await setStatus(tester, ConnectionStatus.unreachable);
      await block(tester, {NetworkHostCategory.pangeaApi});

      expect(find.text(bannerText), findsOneWidget);
      expect(find.text(unreachableText), findsNothing);
    });

    testWidgets(
      'stays hidden for a blocked chat server, even with that banner dismissed',
      (tester) async {
        await tester.pumpWidget(app(const SizedBox()));
        await tester.pumpAndSettle();
        await setStatus(tester, ConnectionStatus.unreachable);
        await block(tester, {NetworkHostCategory.chatServer});
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pump();

        expect(find.text(bannerText), findsNothing);
        expect(find.text(unreachableText), findsNothing);
      },
    );

    testWidgets('once dismissed, comes back when the state changes', (
      tester,
    ) async {
      await tester.pumpWidget(app(const SizedBox()));
      await tester.pumpAndSettle();
      await setStatus(tester, ConnectionStatus.offline);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pump();
      expect(find.text(offlineText), findsNothing);

      await setStatus(tester, ConnectionStatus.unreachable);
      expect(find.text(unreachableText), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pump();
      expect(find.text(unreachableText), findsNothing);

      await setStatus(tester, ConnectionStatus.connected);
      await setStatus(tester, ConnectionStatus.unreachable);
      expect(find.text(unreachableText), findsOneWidget);
    });
  });

  // #9513 — practice that works offline, offered from the banner.
  group('the practice offer', () {
    const offerText = 'Practice vocab while you wait';
    final holder = PracticeSessionHolder.instance;
    late GoRouter router;

    setUp(() {
      ConnectionBanner.canPracticeOffline = () async => true;
      router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const Scaffold()),
        ],
      );
    });

    tearDown(() {
      ConnectionBanner.canPracticeOffline =
          AnalyticsPracticeSessionRepo.canStartOffline;
      holder.end();
      router.dispose();
    });

    Widget routedApp() => MaterialApp.router(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      routerConfig: router,
      builder: (context, child) =>
          ConnectionBanner(router: router, child: child),
    );

    /// One pump for the banner, one for the offer's check to land.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    testWidgets('is made on every banner that says Pangea is out of reach', (
      tester,
    ) async {
      await tester.pumpWidget(routedApp());
      await tester.pumpAndSettle();
      expect(find.text(offerText), findsNothing);

      status.value = ConnectionStatus.offline;
      await settle(tester);
      expect(find.text(offlineText), findsOneWidget);
      expect(find.text(offerText), findsOneWidget);

      status.value = ConnectionStatus.unreachable;
      await settle(tester);
      expect(find.text(unreachableText), findsOneWidget);
      expect(find.text(offerText), findsOneWidget);

      blocked.value = {NetworkHostCategory.pangeaApi};
      await settle(tester);
      expect(find.text(bannerText), findsOneWidget);
      expect(find.text(offerText), findsOneWidget);

      blocked.value = {};
      status.value = ConnectionStatus.backOnline;
      await settle(tester);
      expect(find.text(offerText), findsNothing);
    });

    testWidgets('is not made without a session\'s worth of saved meanings', (
      tester,
    ) async {
      ConnectionBanner.canPracticeOffline = () async => false;
      await tester.pumpWidget(routedApp());
      await tester.pumpAndSettle();

      status.value = ConnectionStatus.offline;
      await settle(tester);
      expect(find.text(offlineText), findsOneWidget);
      expect(find.text(offerText), findsNothing);
    });

    testWidgets('dismisses the banner and opens vocab practice', (
      tester,
    ) async {
      await tester.pumpWidget(routedApp());
      await tester.pumpAndSettle();
      status.value = ConnectionStatus.offline;
      await settle(tester);

      await tester.tap(find.text(offerText));
      await tester.pumpAndSettle();

      expect(find.text(offlineText), findsNothing);
      final uri = router.routeInformationProvider.value.uri;
      expect(practiceIsOpen(uri), isTrue);
      expect(uri.toString(), contains('vocab'));
    });

    testWidgets('is not made while the practice page is open', (tester) async {
      await tester.pumpWidget(routedApp());
      await tester.pumpAndSettle();
      router.go(
        WorkspaceNav.openPractice(
          router.routeInformationProvider.value.uri,
          ConstructTypeEnum.vocab,
        ),
      );
      await tester.pumpAndSettle();

      status.value = ConnectionStatus.offline;
      await settle(tester);
      expect(find.text(offlineText), findsOneWidget);
      expect(find.text(offerText), findsNothing);
    });

    testWidgets('waits while a practice session is in progress', (
      tester,
    ) async {
      await tester.pumpWidget(routedApp());
      await tester.pumpAndSettle();
      holder
          .claim(ConstructTypeEnum.morph)
          .sessionController
          .session = AnalyticsPracticeSessionModel(
        type: ConstructTypeEnum.morph,
        practiceTargets: [
          AnalyticsPracticeTarget(
            target: PracticeTarget(
              tokens: [
                PangeaToken(
                  text: PangeaTokenText.fromJson({
                    'content': 'gato',
                    'offset': 0,
                  }),
                  lemma: Lemma(text: 'gato', saveVocab: true, form: 'gato'),
                  pos: 'NOUN',
                  morph: const {},
                ),
              ],
              exerciseType: PracticeExerciseTypeEnum.lemmaMeaning,
            ),
          ),
        ],
        userL1: 'en',
        userL2: 'es',
      );
      holder.bump();
      expect(holder.hasUnfinishedSession, isTrue);

      status.value = ConnectionStatus.offline;
      await settle(tester);
      expect(find.text(offlineText), findsOneWidget);
      expect(find.text(offerText), findsNothing);

      holder.end();
      await settle(tester);
      expect(find.text(offerText), findsOneWidget);
    });
  });

  testWidgets('a note takes a blocked feature\'s place, and only its own', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Column(
          children: [
            Expanded(
              child: FilteredNetworkNote(
                category: NetworkHostCategory.video,
                child: Text('player'),
              ),
            ),
            FilteredNetworkNote(category: NetworkHostCategory.map),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('player'), findsOneWidget);

    await block(tester, {NetworkHostCategory.video});
    expect(find.text('player'), findsNothing);
    expect(find.text('This network blocks videos.'), findsOneWidget);
    expect(find.text('This network blocks the map.'), findsNothing);
  });
}
