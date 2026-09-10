import 'package:flutter/foundation.dart';

/// One-shot "the learner just opened a panel from the user cluster" signal.
///
/// Armed by the cluster's open methods right before they navigate, and taken
/// by the first `PanelEntryFocus` that mounts, which then moves keyboard focus
/// from the pressed cluster button onto the panel's first control
/// (routing.instructions.md, "Every panel is a named group to assistive
/// tech"). A panel opened any other way — a URL, the rail, a map pin — never
/// arms it, so focus stays where it was.
///
/// An arm expires after [ttl]: a press that changed nothing (the panel was
/// already open, so nothing mounted) must not move focus on some unrelated
/// open seconds later.
class PanelEntryIntent {
  PanelEntryIntent._() : _now = DateTime.now;

  @visibleForTesting
  PanelEntryIntent.forTest({required DateTime Function() now}) : _now = now;

  static final PanelEntryIntent instance = PanelEntryIntent._();

  static const Duration ttl = Duration(seconds: 1);

  final DateTime Function() _now;
  DateTime? _armedAt;

  void arm() => _armedAt = _now();

  /// Whether a live arm was pending. Clears it either way.
  bool take() {
    final armedAt = _armedAt;
    _armedAt = null;
    return armedAt != null && _now().difference(armedAt) <= ttl;
  }
}
