import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/routes.dart';
import 'package:fluffychat/features/navigation/legacy_redirects.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/widgets/matrix.dart';

void main() {
  const room = '!email:other.example';
  const event = r'$message/with:punctuation,=&';
  final path =
      '/room/${Uri.encodeComponent(room)}/${Uri.encodeComponent(event)}';

  RoomPanelToken roomToken(Uri uri) => uri.query
      .split('&')
      .singleWhere((part) => part.startsWith('left='))
      .substring(5)
      .split(',')
      .map(PanelToken.parse)
      .whereType<RoomPanelToken>()
      .single;

  for (final location in [path, '/#$path']) {
    testWidgets('email link resolves at router startup: $location', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: location,
        redirect: (context, state) => LegacyRedirects.handle(state.uri),
        onException: AppRoutes.onException,
        routes: [
          GoRoute(path: '/', builder: (context, state) => const Text('World')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final resolved = router.routeInformationProvider.value.uri;
      expect(resolved.path, '/');
      expect(roomToken(resolved).param!.id, room);
      expect(roomToken(resolved).param!.eventId, event);
      expect(LegacyRedirects.handle(resolved), isNull);
      expect(find.text('World'), findsOneWidget);
    });
  }

  test('native email replay preserves the room and event', () {
    final incoming = MatrixState.incomingUriToPath(
      Uri.parse('https://app.pangea.chat/#$path'),
    );
    final resolved = Uri.parse(LegacyRedirects.handle(Uri.parse(incoming))!);
    expect(roomToken(resolved).param!.id, room);
    expect(roomToken(resolved).param!.eventId, event);
  });

  test('room-only invite opens its room', () {
    final resolved = Uri.parse(
      LegacyRedirects.handle(Uri.parse('/room/$room'))!,
    );
    expect(roomToken(resolved).param!.id, room);
    expect(roomToken(resolved).param!.eventId, isNull);
  });

  for (final signedIn in [true, false]) {
    testWidgets(
      'unknown URL recovers through auth guard (signed in: $signedIn)',
      (tester) async {
        var guardCalls = 0;
        final router = GoRouter(
          initialLocation: '/unknown/nested/path',
          redirect: (context, state) => LegacyRedirects.handle(state.uri),
          onException: AppRoutes.onException,
          routes: [
            GoRoute(
              path: '/',
              redirect: (context, state) {
                guardCalls++;
                return signedIn ? null : '/home';
              },
              builder: (context, state) => const Text('World'),
            ),
            GoRoute(
              path: '/home',
              builder: (context, state) => const Text('Home'),
            ),
            GoRoute(
              path: '/next',
              builder: (context, state) => const Text('Next'),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(guardCalls, greaterThan(0));
        expect(find.text(signedIn ? 'World' : 'Home'), findsOneWidget);
        router.push('/next');
        await tester.pumpAndSettle();
        router.pop();
        await tester.pumpAndSettle();
        expect(find.text(signedIn ? 'World' : 'Home'), findsOneWidget);
        router.go('/another/unknown/path');
        await tester.pumpAndSettle();
        expect(find.text(signedIn ? 'World' : 'Home'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
