import 'package:flutter/widgets.dart';

import 'package:fluffychat/routes/chat/activity_sessions/activity_media_visibility.dart';

/// Registers [child] — the activity's media carousel in the chat timeline —
/// with [visibility] for as long as it is mounted.
class ActivityMediaVisibilityTarget extends StatefulWidget {
  final ActivityMediaVisibility visibility;
  final Widget child;

  const ActivityMediaVisibilityTarget({
    super.key,
    required this.visibility,
    required this.child,
  });

  @override
  State<ActivityMediaVisibilityTarget> createState() =>
      _ActivityMediaVisibilityTargetState();
}

class _ActivityMediaVisibilityTargetState
    extends State<ActivityMediaVisibilityTarget> {
  @override
  void initState() {
    super.initState();
    widget.visibility.attach(context);
  }

  @override
  void didUpdateWidget(ActivityMediaVisibilityTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibility != widget.visibility) {
      oldWidget.visibility.detach(context);
      widget.visibility.attach(context);
    }
  }

  @override
  void dispose() {
    widget.visibility.detach(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
