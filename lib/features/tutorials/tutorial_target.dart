import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Registers [child] as a tutorial spotlight target, so a step can point at it
/// by id.
///
/// **One mounted claimant per id, ever.** An id resolves to a single
/// `LabeledGlobalKey` in the overlay registry, and a GlobalKey may only be
/// attached to one mounted widget at a time — two claimants throw. So a widget
/// that renders in more than one place takes its id as a nullable parameter and
/// a null [targetId] is a plain pass-through: the mount site the tutorial
/// actually points at passes the id, every other one passes nothing. Everywhere
/// an id is declared or claimed, the comment says *which* mount site claims it;
/// the reason it has to be only one is here.
class TutorialTarget extends StatefulWidget {
  final String? targetId;

  /// Fires once, post-frame, when this target mounts while claiming an id
  /// (and again if a null id later becomes one). A trigger that gates on "is
  /// the target on screen" listens here, because the target can arrive after
  /// every other signal has already fired — a mobile sheet finishing its
  /// expand animation, a list landing — and a trigger keeps asking
  /// (tutorials.instructions.md).
  final VoidCallback? onMounted;

  final Widget child;

  const TutorialTarget({
    required this.targetId,
    required this.child,
    this.onMounted,
    super.key,
  });

  /// Brings the target claiming [targetId] fully into view in whatever
  /// scrollable hosts it, before a step measures it. Nothing can scroll once
  /// the tutorial is up — a tap step absorbs every pointer, and an armed
  /// step's spotlight passes taps but not scrolls — so a target that starts
  /// below the fold stays there for the whole run (#9029). End first, then
  /// start: a target taller than the viewport ends with its top edge showing,
  /// which is the slice the card anchors to. Each pass is a no-op for a target
  /// already fully visible, and the whole thing is a no-op for one that is not
  /// mounted or not inside a scrollable.
  static Future<void> ensureVisible(String targetId) async {
    for (final policy in const [
      ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    ]) {
      final targetContext = MatrixState.pAnyState
          .layerLinkAndKey(targetId)
          .key
          .currentContext;
      if (targetContext == null || !targetContext.mounted) return;
      await Scrollable.ensureVisible(
        targetContext,
        alignmentPolicy: policy,
        duration: FluffyThemes.animationDuration,
      );
    }
  }

  /// The target's box on screen, cut down to the slice its nearest scroll
  /// viewport shows. Measured whole, a list running below the fold punched
  /// its hole through the controls under the viewport and off the sheet
  /// (#9029). A target with no viewport above it measures whole. A slice that
  /// is entirely scrolled away collapses to a point on the viewport's edge
  /// rather than disappearing: scrolled out of view is not gone, and a missing
  /// rect reads to the overlay as "every target vanished".
  static Rect visibleRect(RenderBox box) {
    final rect = box.localToGlobal(Offset.zero) & box.size;
    // Typed as the root class so the `is` check promotes: every Flutter
    // viewport is a RenderBox, but the mixin itself is not one.
    final RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is! RenderBox) return rect;
    final viewportRect = viewport.localToGlobal(Offset.zero) & viewport.size;
    final clipped = rect.intersect(viewportRect);
    if (!clipped.isEmpty) return clipped;
    return Rect.fromLTWH(
      clipped.left.clamp(viewportRect.left, viewportRect.right).toDouble(),
      clipped.top.clamp(viewportRect.top, viewportRect.bottom).toDouble(),
      0.0,
      0.0,
    );
  }

  @override
  State<TutorialTarget> createState() => _TutorialTargetState();
}

class _TutorialTargetState extends State<TutorialTarget> {
  @override
  void initState() {
    super.initState();
    _notifyIfClaiming();
  }

  @override
  void didUpdateWidget(covariant TutorialTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetId == null && widget.targetId != null) {
      _notifyIfClaiming();
    }
  }

  void _notifyIfClaiming() {
    final onMounted = widget.onMounted;
    if (widget.targetId == null || onMounted == null) return;
    // Post-frame, so the render box exists by the time the listener checks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onMounted();
    });
  }

  @override
  Widget build(BuildContext context) {
    final targetId = widget.targetId;
    if (targetId == null) return widget.child;
    final target = MatrixState.pAnyState.layerLinkAndKey(targetId);
    return CompositedTransformTarget(
      link: target.link,
      child: Stack(
        // Lay out and paint exactly as the bare child did: the child keeps the
        // incoming constraints, and nothing it paints outside its box is
        // clipped.
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        alignment: Alignment.topLeft,
        children: [
          widget.child,
          // The registry's GlobalKey rides a childless leaf filling the
          // child's box — it is only ever read for the target's rect
          // ([PangeaAnyState.getRenderBox]) — rather than wrapping the child.
          // A GlobalKey carries its whole subtree to wherever its host moves
          // next, and these hosts move: re-keying a panel on a token param
          // change, or growing a course card out of the context bar, both swap
          // the host in one frame. Wrapping therefore reparented a page-sized
          // subtree, and doing that from inside a LayoutBuilder's build throws
          // as soon as the subtree holds a shown OverlayPortal — the overlay
          // child is adopted mid-layout (#9046). The leaf measures the same
          // rect and carries nothing.
          Positioned.fill(child: SizedBox.expand(key: target.key)),
        ],
      ),
    );
  }
}
