import 'package:flutter/foundation.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

/// Which metric the right-docked analytics panel shows, and (optionally) the
/// vocab/grammar construct whose detail is open to the left of the summary.
@immutable
class AnalyticsPanelState {
  final AnalyticsPanelTab tab;
  final ConstructIdentifier? construct;

  const AnalyticsPanelState(this.tab, {this.construct});

  AnalyticsPanelState withConstruct(ConstructIdentifier? c) =>
      AnalyticsPanelState(tab, construct: c);

  @override
  bool operator ==(Object other) =>
      other is AnalyticsPanelState &&
      other.tab == tab &&
      other.construct == construct;

  @override
  int get hashCode => Object.hash(tab, construct);
}

/// App-state for the right-docked analytics panel (the top-right cluster's
/// trackers). **Deliberately not in the URL.** The panel is a persistent
/// personal companion: navigating the left content — the nav rail, a chat, a
/// course, a map pin — must never close it (the "interact with your stuff while
/// you work" model from the world designs). So it lives here, decoupled from
/// `context.go`, instead of as a `?analytics=` query param that every left-side
/// navigation would drop. Opened by the cluster trackers; closed by the panel's
/// own close button. The activity *detail* is a chat and stays URL-routed.
abstract class AnalyticsPanelController {
  static final ValueNotifier<AnalyticsPanelState?> notifier =
      ValueNotifier<AnalyticsPanelState?>(null);

  static AnalyticsPanelState? get value => notifier.value;

  static bool get isOpen => notifier.value != null;

  /// Open (or switch to) [tab]'s summary; clears any open construct detail.
  static void open(AnalyticsPanelTab tab) {
    notifier.value = AnalyticsPanelState(tab);
  }

  /// Open a vocab/grammar construct's detail (switching tab if needed).
  static void openConstruct(AnalyticsPanelTab tab, ConstructIdentifier construct) {
    notifier.value = AnalyticsPanelState(tab, construct: construct);
  }

  /// Drop the open detail, returning to the summary (keeps the panel open).
  static void clearConstruct() {
    final current = notifier.value;
    if (current != null) notifier.value = current.withConstruct(null);
  }

  /// Close the panel entirely.
  static void close() {
    notifier.value = null;
  }
}
