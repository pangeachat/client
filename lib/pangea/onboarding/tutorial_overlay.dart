import 'package:fluffychat/pangea/common/widgets/anchored_overlay_widget.dart';
import 'package:fluffychat/pangea/common/widgets/tutorial_overlay_message.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_anchor_registry.dart';
import 'package:fluffychat/pangea/onboarding/tutorial_manager.dart';
import 'package:flutter/material.dart';

class TutorialOverlay extends StatefulWidget {
  final TutorialManager manager;

  const TutorialOverlay({super.key, required this.manager});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  @override
  void initState() {
    super.initState();
    // optional: listen for manager updates if using Stream/ChangeNotifier
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.manager.current;
    if (step == null) return const SizedBox();
    final key = TutorialAnchorRegistry.instance.get(step.anchorId);
    final ctx = key?.currentContext;
    if (ctx == null) return const SizedBox();

    final box = ctx.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);
    final cellRect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      box.size.width,
      box.size.height,
    );

    return IgnorePointer(
      child: AnchoredOverlayWidget(
        anchorRect: cellRect,
        borderRadius: step.borderRadius,
        padding: step.padding,
        overlayKey: step.anchorId,
        child: TutorialOverlayMessage(step.message),
      ),
    );
  }
}
