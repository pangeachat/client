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
/// listener actually delivers a shared link — a post-frame `router.go()` call
/// after the app has already booted, not `initialLocation`.
///
/// The builder calls [userIdFromUrlParam], the same single function
/// `routes.dart` calls, so these pin the real read-side behavior rather than a
/// copy of it. Guards against the id reaching the homeserver still
/// percent-encoded, which reads as an invalid mxid.
const _homeDomain = 'staging.pangea.chat';

/// Boots the router, replays [sharedLink] the way a tapped share link arrives,
/// and returns the mxid the invite route resolved.
Future<String?> _resolve(WidgetTester tester, String sharedLink) async {
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
          captured = userIdFromUrlParam(
            state.pathParameters['userID']!,
            domain: _homeDomain,
          );
          return const SizedBox();
        },
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();

  router.go(MatrixState.incomingUriToPath(Uri.parse(sharedLink)));
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  testWidgets(
    'a home-server id rides shortened and resolves to the full mxid',
    (tester) async {
      // The link fluffy_share.dart builds: shortUserId, then encoded once.
      expect(
        await _resolve(
          tester,
          'https://app.staging.pangea.chat/#/invite_user/%40william11',
        ),
        '@william11:$_homeDomain',
      );
    },
  );

  testWidgets('a foreign-homeserver id keeps its own domain', (tester) async {
    expect(
      await _resolve(
        tester,
        'https://app.staging.pangea.chat/#/invite_user/%40will%3Amatrix.org',
      ),
      '@will:matrix.org',
    );
  });

  testWidgets('a double-encoded link still resolves (the reported bug)', (
    tester,
  ) async {
    // A client that linkifies the shared message can encode it a second time.
    // The router decodes once, which on its own would leave `%40william11...`
    // and reach the homeserver as an invalid mxid.
    expect(
      await _resolve(
        tester,
        'https://app.staging.pangea.chat/#/invite_user/%2540william11%253Astaging.pangea.chat',
      ),
      '@william11:$_homeDomain',
    );
  });

  testWidgets('a malformed link does not throw out of the route builder', (
    tester,
  ) async {
    expect(
      await _resolve(
        tester,
        'https://app.staging.pangea.chat/#/invite_user/100%25',
      ),
      // Left as given; it fails id validation downstream, not here.
      '100%:$_homeDomain',
    );
    expect(tester.takeException(), isNull);
  });
}
