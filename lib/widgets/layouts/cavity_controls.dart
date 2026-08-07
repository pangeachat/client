import 'package:flutter/widgets.dart';

/// Lets a surface hosted in the mobile nav cavity drive the cavity that holds
/// it. Today that's just [expandToFull], which the activity plan's minimized
/// CTA chips call so tapping an action (Start, Join, Completed) maximizes the
/// sheet before it shows the role picker / session list — otherwise the new
/// view would stay dropped by the minimized `LayoutBuilder`. Provided by
/// `MobileNavWidget`; absent on the wide web panel (no cavity), where the
/// getter returns null and the action just runs. See
/// activity-start-page.instructions.md.
class CavityControls extends InheritedWidget {
  final VoidCallback? expandToFull;

  const CavityControls({
    required this.expandToFull,
    required super.child,
    super.key,
  });

  static VoidCallback? maybeExpandToFull(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CavityControls>()?.expandToFull;

  // The callback closes over the cavity's State, so it stays valid across
  // rebuilds — dependents only invoke it, never rebuild on it.
  @override
  bool updateShouldNotify(CavityControls oldWidget) => false;
}
