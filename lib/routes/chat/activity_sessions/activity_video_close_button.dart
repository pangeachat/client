import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/focus_ring_tap_target.dart';

/// The X that closes a playing activity video: the hero's strip above the
/// inline player and the app bar of [ActivityVideoScreen]. Both sit on the
/// video's black letterbox in either theme, so the X inks white, and
/// Material's own focus wash is invisible there (#9280), so the X wears the
/// shared gold focus ring.
class ActivityVideoCloseButton extends StatelessWidget {
  final VoidCallback onPressed;

  const ActivityVideoCloseButton({required this.onPressed, super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: L10n.of(context).close,
    style: ButtonStyle(side: FocusRingTapTarget.ringSideProperty(context)),
    icon: const Icon(Icons.close, color: Colors.white),
    onPressed: onPressed,
  );
}
