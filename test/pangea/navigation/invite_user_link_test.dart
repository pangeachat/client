import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/legacy_redirects.dart';
import 'package:fluffychat/features/navigation/user_id_url.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// End-to-end regression coverage for the `/invite_user/:userID` link
/// (Share invite link), across **both** ways a shared link reaches the router,
/// using the same GoRouter wiring as `fluffy_chat_app.dart`:
///
/// - **web** — `usePathUrlStrategy` means the router boots from the real path,
///   so the link is the initial location. A `/#/` link lands here as `/` and
///   never routes (#7922 reopened: worked on iOS, dead on web).
/// - **native** — app_links replays the link post-boot via
///   `MatrixState.incomingUriToPath`, which unwraps a fragment.
///
/// Links come from [inviteLinkForUser], the same function `fluffy_share.dart`
/// ships, and the builder calls [userIdFromUrlParam], the same one
/// `routes.dart` calls — so these pin real behavior, not a copy of it.
const _homeDomain = 'staging.pangea.chat';
const _frontend = 'https://app.staging.pangea.chat';

GoRouter _router(void Function(String) onInvite, String initialLocation) =>
    GoRouter(
      initialLocation: initialLocation,
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
            onInvite(
              userIdFromUrlParam(
                state.pathParameters['userID']!,
                domain: _homeDomain,
              ),
            );
            return const SizedBox();
          },
        ),
      ],
    );

/// Web: the router boots directly from the shared link's path.
Future<String?> _resolveOnWeb(WidgetTester tester, String sharedLink) async {
  String? captured;
  final uri = Uri.parse(sharedLink);
  // What the browser hands the path-strategy router: path + query, no fragment.
  final location = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  await tester.pumpWidget(
    MaterialApp.router(routerConfig: _router((v) => captured = v, location)),
  );
  await tester.pumpAndSettle();
  return captured;
}

/// Native: app_links replays the link after the app has already booted.
Future<String?> _resolveOnNative(WidgetTester tester, String sharedLink) async {
  String? captured;
  final router = _router((v) => captured = v, '/');
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();

  router.go(MatrixState.incomingUriToPath(Uri.parse(sharedLink)));
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  group('the link the app actually shares', () {
    test('is a path, never a fragment', () {
      // A `/#/` link is invisible to the path-strategy router: the whole
      // reason the fix worked on iOS and did nothing on web (#7922 reopened).
      final link = inviteLinkForUser(
        _frontend,
        '@william11:$_homeDomain',
        domain: _homeDomain,
      );
      expect(link, '$_frontend/invite_user/%40william11');
      expect(link, isNot(contains('#')));
      expect(Uri.parse(link).fragment, isEmpty);
    });

    testWidgets('resolves on web, where the router boots from the path', (
      tester,
    ) async {
      final link = inviteLinkForUser(
        _frontend,
        '@william11:$_homeDomain',
        domain: _homeDomain,
      );
      expect(await _resolveOnWeb(tester, link), '@william11:$_homeDomain');
    });

    testWidgets('resolves on native, replayed by app_links', (tester) async {
      final link = inviteLinkForUser(
        _frontend,
        '@william11:$_homeDomain',
        domain: _homeDomain,
      );
      expect(await _resolveOnNative(tester, link), '@william11:$_homeDomain');
    });
  });

  group('reading the id back', () {
    testWidgets('a foreign-homeserver id keeps its own domain', (tester) async {
      expect(
        await _resolveOnWeb(
          tester,
          '$_frontend/invite_user/%40will%3Amatrix.org',
        ),
        '@will:matrix.org',
      );
    });

    testWidgets('a double-encoded link still resolves', (tester) async {
      // A client that linkifies the shared message can encode it a second
      // time. The router decodes once, which on its own would leave
      // `%40william11...` and reach the homeserver as an invalid mxid.
      expect(
        await _resolveOnWeb(
          tester,
          '$_frontend/invite_user/%2540william11%253Astaging.pangea.chat',
        ),
        '@william11:$_homeDomain',
      );
    });

    testWidgets('a malformed link does not throw out of the route builder', (
      tester,
    ) async {
      expect(
        await _resolveOnWeb(tester, '$_frontend/invite_user/100%25'),
        // Left as given; it fails id validation downstream, not here.
        '100%:$_homeDomain',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
