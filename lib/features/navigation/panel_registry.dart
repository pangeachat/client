/// Which column a panel belongs to, which fixes its role and its justification.
enum PanelColumn { left, right }

/// Static layout metadata for a panel type. Pure data (no widgets), so the URL
/// parser in `route_facts.dart` and the width allocator can read it without a
/// widget binding; the widget builder is resolved separately by the shell.
/// See `routing.instructions.md`.
class PanelDef {
  final PanelColumn column;
  final double minWidth;
  final double idealWidth;

  /// Higher-priority panels stay full longer and collapse last under pressure.
  final int priority;

  /// An exclusive panel collapses the others while it is open (immersive).
  final bool exclusive;

  const PanelDef({
    required this.column,
    required this.minWidth,
    required this.idealWidth,
    required this.priority,
    this.exclusive = false,
  });
}

/// The known panel types. Adding a surface is one entry here plus its builder in
/// the shell. Widths reuse the shell's established sizes: list 380, content max
/// 720, opaque floor 360, right card 488. Priorities and widths are tunable.
abstract class PanelRegistry {
  static const Map<String, PanelDef> defs = {
    // Left — navigation and social.
    'chats': PanelDef(
      column: PanelColumn.left,
      minWidth: 300,
      idealWidth: 380,
      priority: 30,
    ),
    'room': PanelDef(
      column: PanelColumn.left,
      minWidth: 360,
      idealWidth: 720,
      priority: 80,
    ),
    'course': PanelDef(
      column: PanelColumn.left,
      minWidth: 360,
      idealWidth: 720,
      priority: 60,
    ),
    'settings': PanelDef(
      column: PanelColumn.left,
      minWidth: 360,
      idealWidth: 600,
      priority: 50,
    ),
    'profile': PanelDef(
      column: PanelColumn.left,
      minWidth: 360,
      idealWidth: 600,
      priority: 50,
    ),
    // Right — personal learning and review.
    'analytics': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      idealWidth: 488,
      priority: 40,
    ),
    'vocab': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      idealWidth: 488,
      priority: 50,
    ),
    'grammar': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      idealWidth: 488,
      priority: 50,
    ),
    'review': PanelDef(
      column: PanelColumn.right,
      minWidth: 360,
      idealWidth: 488,
      priority: 70,
    ),
  };

  static PanelDef? defFor(String type) => defs[type];
}
