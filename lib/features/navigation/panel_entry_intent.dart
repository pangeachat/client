import 'package:flutter/widgets.dart';

/// One-shot "the learner just opened a panel from the user cluster or the
/// rail" signal.
///
/// Armed by the cluster's open methods and the rail's course items right
/// before they navigate, and taken by the first `PanelEntryFocus` that mounts,
/// which then moves keyboard focus from the pressed control onto the panel's
/// named group (routing.instructions.md, "Every panel is a named group to
/// assistive tech"). A panel opened any other way — a URL, the rail's section
/// icons, a map pin — never arms it, so focus stays where it was.
///
/// An arm expires after [ttl]: a press that changed nothing (the panel was
/// already open, so nothing mounted) must not move focus on some unrelated
/// open seconds later.
///
/// An arm may name its target panel. A closed detail returns focus to its
/// parent, which is either folded beneath it and about to mount, or already on
/// screen beside it, where nothing mounts; panels on screen hear a named arm
/// through this notifier.
class PanelEntryIntent extends ChangeNotifier {
  PanelEntryIntent._() : _now = DateTime.now;

  @visibleForTesting
  PanelEntryIntent.forTest({required DateTime Function() now}) : _now = now;

  static final PanelEntryIntent instance = PanelEntryIntent._();

  static const Duration ttl = Duration(seconds: 1);

  final DateTime Function() _now;
  DateTime? _armedAt;
  Object? _target;

  /// Arms the claim for the next panel that mounts, or with [target] for that
  /// panel alone, whether it mounts next or is already on screen.
  void arm({Object? target}) {
    _armedAt = _now();
    _target = target;
    notifyListeners();
  }

  /// [arm] for a navigation that destroys the pressed control: a page pushed
  /// or popped within a panel swaps its token, so the panel is rebuilt. Drops
  /// the focus history first, or the framework hands focus to the last control
  /// still alive — the rail item — until the new page claims it (the
  /// onboarding swap's fix, #7582).
  void armForSwap({Object? target}) {
    FocusManager.instance.primaryFocus?.unfocus();
    arm(target: target);
  }

  /// Whether a live arm was pending for [panel], clearing it if it was this
  /// panel's to take. A panel already on screen passes [mounting] false and
  /// may take only an arm that names it; an unnamed arm waits for the panel
  /// that mounts.
  bool take({Object? panel, bool mounting = true}) {
    if (_target == null ? !mounting : _target != panel) return false;
    final armedAt = _armedAt;
    _armedAt = null;
    _target = null;
    return armedAt != null && _now().difference(armedAt) <= ttl;
  }
}
