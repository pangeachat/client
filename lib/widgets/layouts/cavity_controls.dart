import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Lets a surface hosted in the mobile nav cavity drive the cavity that holds
/// it:
///
/// - [expandToFull], which the activity plan's minimized CTA chips call so
///   tapping an action (Start, Join, Completed) maximizes the sheet before it
///   shows the role picker / session list — otherwise the new view would stay
///   dropped by the minimized `LayoutBuilder`.
/// - [toggleCollapse] with [expanded], which a FLOOR cavity's chevron uses as
///   its whole affordance: the course panel cannot be dismissed, so one
///   control moves it between its peek and full instead of closing it (#8816;
///   routing.instructions.md → Closing a panel).
///
/// Provided by `MobileNavWidget`; absent on the wide web panel (no cavity),
/// where the getters return null and the action just runs. See
/// activity-start-page.instructions.md.
class CavityControls extends InheritedWidget {
  final VoidCallback? expandToFull;

  /// Collapse an expanded cavity to its rest floor, or re-expand a resting
  /// one. A floor cavity never reaches zero, so this is a two-way toggle
  /// rather than a close.
  final VoidCallback? toggleCollapse;

  /// Whether the cavity currently sits above its rest floor, so a chevron can
  /// rotate to say which way it goes. A listenable rather than a plain field
  /// because [updateShouldNotify] is false: the chevron rebuilds itself on a
  /// height change without rebuilding the hosted surface under it.
  final ValueListenable<bool>? expanded;

  const CavityControls({
    required this.expandToFull,
    required super.child,
    this.toggleCollapse,
    this.expanded,
    super.key,
  });

  static VoidCallback? maybeExpandToFull(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CavityControls>()?.expandToFull;

  static CavityControls? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CavityControls>();

  // The callbacks close over the cavity's State, so they stay valid across
  // rebuilds — dependents only invoke them, never rebuild on them. A chevron's
  // rotation rides [expanded] instead.
  @override
  bool updateShouldNotify(CavityControls oldWidget) => false;
}
