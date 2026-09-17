import 'package:flutter/rendering.dart';

/// Opens a widget's long-press menu from a screen reader's "show menu"
/// command on web (accessibility.instructions.md § Long-press menus).
class ShowMenuLongPress {
  /// The semantics identifier a long-pressable node carries to opt in.
  static const semanticsIdentifier = 'show-menu-long-press';

  /// Performs the long-press action of the semantics node [nodeId]. Returns
  /// false, doing nothing, when no view holds a long-pressable node with that
  /// id.
  static bool perform(int nodeId) {
    for (final view in RendererBinding.instance.renderViews) {
      final owner = view.owner?.semanticsOwner;
      final root = owner?.rootSemanticsNode;
      final node = root == null ? null : _find(root, nodeId);
      if (owner == null || node == null) continue;
      if (!node.getSemanticsData().hasAction(SemanticsAction.longPress)) {
        return false;
      }
      owner.performAction(nodeId, SemanticsAction.longPress);
      return true;
    }
    return false;
  }

  static SemanticsNode? _find(SemanticsNode node, int nodeId) {
    if (node.id == nodeId) return node;
    SemanticsNode? found;
    node.visitChildren((child) {
      found = _find(child, nodeId);
      return found == null;
    });
    return found;
  }
}
