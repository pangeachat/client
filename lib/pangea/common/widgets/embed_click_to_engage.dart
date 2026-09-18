import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/widgets/embed_pointer_shield.dart';

/// Hands the browser's pointer to an embedded player only once the learner
/// clicks it, and takes it back when they move away.
///
/// On web an embed is a real `<iframe>`/`<video>` that takes every mouse event
/// over it — so while the learner is only passing through, the page around it
/// goes dead: a wheel scrolls nothing, because events inside a cross-origin
/// frame never reach the page, and a widget floating over the embed never sees
/// the click (#9063). Shielded, the surface behaves like the rest of the page;
/// engaged, the embed's own controls — scrub, volume, captions — work as they
/// always did. The click that engages is absorbed by the shield, so [onEngage]
/// spends it on play/pause, which is what clicking a video does anyway.
///
/// Off web Flutter owns every pixel and the embed is engaged from the start.
class EmbedClickToEngage extends StatefulWidget {
  /// The embed. It sizes the widget, so it must not be a bare platform view
  /// with no constraints of its own.
  final Widget child;

  /// Spends the click the shield absorbed — play/pause on the embed's
  /// controller.
  final VoidCallback? onEngage;

  /// False leaves [child] alone. Defaults to the platforms that have a DOM to
  /// lose the pointer to; a test can turn the shield on to exercise it.
  final bool enabled;

  const EmbedClickToEngage({
    required this.child,
    this.onEngage,
    this.enabled = kIsWeb,
    super.key,
  });

  @override
  State<EmbedClickToEngage> createState() => _EmbedClickToEngageState();
}

class _EmbedClickToEngageState extends State<EmbedClickToEngage> {
  bool _engaged = false;

  void _engage() {
    setState(() => _engaged = true);
    widget.onEngage?.call();
  }

  /// The pointer is only reported to Flutter again once it is back over pixels
  /// Flutter owns — which is exactly when the surface should be scrollable
  /// again.
  void _disengage(PointerExitEvent _) {
    if (_engaged) setState(() => _engaged = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return MouseRegion(
      onExit: _disengage,
      child: Stack(
        children: [
          widget.child,
          if (!_engaged) ...[
            // Below the gesture, above the embed: the shield only stops the
            // embed taking the click, and Flutter still hit-tests it normally.
            const Positioned.fill(child: EmbedPointerShield()),
            Positioned.fill(
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _engage,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
