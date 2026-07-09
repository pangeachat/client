import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';

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
    if (param == null || param.build().isEmpty) return token.type.name;
    switch (token.type) {
      // Identity-only params: a construct's lemma/category, an activity's id
      // and session bindings. The whole param drops.
      case PanelTypesEnum.vocab:
      case PanelTypesEnum.grammar:
      case PanelTypesEnum.activity:
        return token.type.name;
      // A room/session param is `<id>[/<sub-page>]` (RoomToken): the id AND a
      // jump-to-message eventId are identity and drop; a pushed sub-page and
      // its invite filter (a small fixed tab, not personal content) are
      // navigational and stay.
      case PanelTypesEnum.room:
      case PanelTypesEnum.session:
        if (param is! RoomTokenParam) return token.type.name;
        if (param.subpage == null || param.subpage!.isEmpty) {
          return token.type.name;
        }
        final filter = param.filter;
        final sub = filter == null
            ? param.subpage!
            : '${param.subpage}/$filter';
        return '${token.type.name}:$sub';
      // A coursepage param is the bare page, no leading room id (the card's
      // space rides the separate `?c=` context) — an `invite` page may carry a
      // trailing `/<filter>` (WorkspaceNav.openCoursePage), which stays: still
      // just a small fixed tab, not identity.
      // Everything else (settings pages, course tabs, practice modes,
      // analytics tabs, addcourse steps) is a navigational param.
      default:
        return '${token.type.name}:${param.build()}';
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
      final isParentOfOther = open.any((t) => t.type.def.parent == token.type);
      if (isParentOfOther) continue;
      final score = token.type.def.priority;
      if (score > bestScore) {
        best = token;
        bestScore = score;
      }
    }
    return forToken(best ?? open.first);
  }
}
