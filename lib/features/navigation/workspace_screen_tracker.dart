import 'package:flutter/foundation.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/screen_names.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';

/// Emits a GA4 screen view whenever the workspace screen changes, keyed on the
/// token-derived name from [ScreenNames] (google-analytics.instructions.md).
///
/// Deduping by name is what makes the doc's "replaces are silent" rule fall
/// out for free: a width-driven fold/unfold or a refocus does not change the
/// tokens, so the derived name is unchanged and nothing is emitted — only a
/// genuine screen change (open/push/close/pop, or a launch transition) mints a
/// new name. Non-`/` top-level routes (login, onboarding) are page routes,
/// tracked by the [FirebaseAnalyticsObserver], so they are skipped here.
abstract class WorkspaceScreenTracker {
  static String? _lastScreenName;

  /// On web, the current workspace screen name, for `MaterialApp.title` to
  /// mirror into `document.title`. GA's web layer reports by page title (the
  /// web SDK's screen_name param is invisible to built-in reports); mirroring
  /// the screen name — exactly, no prefix — makes web rows merge with app rows
  /// under GA's "Page title and screen name" dimension. Null off the
  /// workspace (page routes keep the app name). Always null on mobile, where
  /// the title labels the OS task switcher instead.
  static final ValueNotifier<String?> webTitle = ValueNotifier(null);

  /// Listen to [router] for the app's lifetime, emitting on each real change.
  static void attach(GoRouter router) {
    final provider = router.routeInformationProvider;
    provider.addListener(() => _onLocation(provider.value.uri));
    _onLocation(provider.value.uri);
  }

  static void _onLocation(Uri uri) {
    if (uri.path != '/') return; // page routes are the observer's job
    final name = ScreenNames.forWorkspace(uri);
    if (name == _lastScreenName) return;
    _lastScreenName = name;
    if (kIsWeb) webTitle.value = name;
    GoogleAnalytics.logScreenView(name);
  }
}
