import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

/// InkWell-backed tap target for opaque-filled controls (#7219): focusable and
/// Enter/Space-activatable where a bare GestureDetector is not, with a gold
/// ring painted while focused — an opaque fill swallows InkWell's
/// behind-the-child focus highlight, so these need an explicit ring. Worn by
/// the top-right cluster's avatar and language flag, and (via
/// [NaviRailItem.focusRingShape]) the nav rail's course avatars (#8724).
class FocusRingTapTarget extends StatefulWidget {
  final VoidCallback onTap;
  final OutlinedBorder shape;
  final Widget child;

  const FocusRingTapTarget({
    required this.onTap,
    required this.shape,
    required this.child,
    super.key,
  });

  @override
  State<FocusRingTapTarget> createState() => _FocusRingTapTargetState();
}

class _FocusRingTapTargetState extends State<FocusRingTapTarget> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      customBorder: widget.shape,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: widget.shape.copyWith(
            side: _focused
                ? BorderSide(color: AppConfig.goldByTheme(context), width: 3.0)
                : BorderSide.none,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
