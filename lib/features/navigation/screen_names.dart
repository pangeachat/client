import 'package:fluffychat/features/navigation/panel_registry.dart';
import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';

/// GA screen names derived from the workspace tokens
/// (google-analytics.instructions.md): a screen name IS the focused panel's
/// token with identity stripped — token syntax, never a parallel naming
/// scheme. Navigational params (a tab, a settings page, a push leaf) stay;
/// identity fields (room and activity ids, construct lemmas) are dropped, so
/// names stay low-cardinality and free of personal content.
abstract class ScreenNames {
  /// The screen name for one panel token.
  static String forToken(PanelToken token) {
    final param = token.param;
    if (param == null || param.isEmpty) return token.type;
    switch (token.type) {
      // Identity-only params: a construct's lemma/category, an activity's id
      // and session bindings. The whole param drops.
      case 'vocab':
      case 'grammar':
      case 'activity':
        return token.type;
      // A room/session param is `<id>[/<sub-page>]`: the id is identity, the
      // pushed sub-page is navigational and stays.
      case 'room':
      case 'session':
        final slash = param.indexOf('/');
        if (slash < 0) return token.type;
        return '${token.type}:${param.substring(slash + 1)}';
      // Everything else (settings pages, course tabs, coursepages, practice
      // modes, analytics tabs, addcourse steps) is a navigational param.
      default:
        return '${token.type}:$param';
    }
  }

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
      final isParentOfOther = open.any(
        (t) => PanelRegistry.defFor(t.type)?.parent == token.type,
      );
      if (isParentOfOther) continue;
      final score = PanelRegistry.defFor(token.type)?.priority ?? 0;
      if (score > bestScore) {
        best = token;
        bestScore = score;
      }
    }
    return forToken(best ?? open.first);
  }
}
