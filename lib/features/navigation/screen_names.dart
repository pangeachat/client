import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

/// GA screen names derived from the workspace tokens
/// (google-analytics.instructions.md): a screen name IS the focused panel's
/// token with identity stripped — token syntax, never a parallel naming
/// scheme. Navigational params (a tab, a settings page, a push leaf) stay;
/// identity fields (room and activity ids, construct lemmas) are dropped, so
/// names stay low-cardinality and free of personal content.
abstract class ScreenNames {
  /// The workspace's screen name: the focused panel — the navigation tree's
  /// leaf (a child always wins over its own open parent; ties between
  /// independent panels break by registry priority) — or `world` for the bare
  /// map. Mirrors the narrow-mode cold-start focus rule
  /// (routing.instructions.md), so analytics and the shell cannot disagree.
  static String forWorkspace(Uri uri) {
    final lists = parseOpenPanels(uri);
    final open = [...lists.right, ...lists.left];
    if (open.isEmpty) return 'world';
    PanelToken? best;
    var bestScore = -1;
    for (final token in open) {
      final isParentOfOther = open.any((t) => t.type.def.parent == token.type);
      if (isParentOfOther) continue;
      final score = token.type.def.priority;
      if (score > bestScore) {
        best = token;
        bestScore = score;
      }
    }
    return (best ?? open.first).screenName;
  }
}
