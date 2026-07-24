import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/legacy_redirects.dart';
import 'package:fluffychat/features/navigation/user_id_url.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// End-to-end regression coverage for the `/invite_user/:userID` link
/// (Share invite link): the same GoRouter wiring as `fluffy_chat_app.dart`
/// (route + top-level redirect), driven the way `MatrixState`'s app_links
/// listener actually delivers a shared link — a post-frame `router.go()`
/// call after the app has already booted, not `initialLocation`. Guards
/// against the id arriving still percent-encoded, which reads to the
/// homeserver as an invalid mxid.
void main() {
  testWidgets('a shared invite link resolves to the fully-decoded, full mxid', (
    tester,
  ) async {
    String? captured;
    final router = GoRouter(
      initialLocation: '/',
      redirect: (context, state) {
        final legacy = LegacyRedirects.handle(state.uri);
        if (legacy != null) return legacy;
        return WorkspaceNav.preserveOpenPanels(state.uri);
      },
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SizedBox()),
        GoRoute(
          path: '/invite_user/:userID',
          builder: (context, state) {
            captured = fullUserId(
              Uri.decodeComponent(state.pathParameters['userID']!),
              domain: 'staging.pangea.chat',
            );
            return const SizedBox();
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // The shortened link fluffy_share.dart now builds for a home-server id.
    final path = MatrixState.incomingUriToPath(
      Uri.parse('https://app.staging.pangea.chat/#/invite_user/%40william11'),
    );
    router.go(path);
    await tester.pumpAndSettle();

    expect(captured, '@william11:staging.pangea.chat');
  });

  testWidgets(
    'a shared invite link for a foreign-homeserver id is left untouched',
    (tester) async {
      String? captured;
      final router = GoRouter(
        initialLocation: '/',
        redirect: (context, state) {
          final legacy = LegacyRedirects.handle(state.uri);
          if (legacy != null) return legacy;
          return WorkspaceNav.preserveOpenPanels(state.uri);
        },
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SizedBox()),
          GoRoute(
            path: '/invite_user/:userID',
            builder: (context, state) {
              captured = fullUserId(
                Uri.decodeComponent(state.pathParameters['userID']!),
                domain: 'staging.pangea.chat',
              );
              return const SizedBox();
            },
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final path = MatrixState.incomingUriToPath(
        Uri.parse(
          'https://app.staging.pangea.chat/#/invite_user/%40will%3Amatrix.org',
        ),
      );
      router.go(path);
      await tester.pumpAndSettle();

      expect(captured, '@will:matrix.org');
    },
  );
}
