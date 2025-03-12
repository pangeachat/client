import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_identifier.dart';
import 'package:flutter/material.dart';

class MessageMorphChoiceItem extends StatefulWidget {
  const MessageMorphChoiceItem({
    super.key,
    required this.onTap,
    required this.isSelected,
    required this.isGold,
    required this.cId,
  });

  final ConstructIdentifier cId;
  final void Function() onTap;
  final bool isSelected;
  final bool? isGold;

  @override
  MessageMorphChoiceItemState createState() => MessageMorphChoiceItemState();
}

class MessageMorphChoiceItemState extends State<MessageMorphChoiceItem> {
  bool _isHovered = false;

  @override
  void didUpdateWidget(covariant MessageMorphChoiceItem oldWidget) {
    if (oldWidget.isSelected != widget.isSelected ||
        oldWidget.isGold != widget.isGold) {
      setState(() {});
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> onTap() async {
    widget.onTap();
  }

  Color get _color {
    if (widget.isSelected && widget.isGold != null) {
      return widget.isGold!
          ? AppConfig.success.withAlpha((0.4 * 255).toInt())
          : AppConfig.warning.withAlpha((0.4 * 255).toInt());
    }
    if (widget.isSelected) {
      return AppConfig.primaryColor.withAlpha((0.4 * 255).toInt());
    }
    return _isHovered
        ? AppConfig.primaryColor.withAlpha((0.2 * 255).toInt())
        : Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            color: _color,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Container(
            padding: const EdgeInsets.all(8.0),
            child: widget.cId.visual,
          ),
        ),
      ),
    );
  }
}
