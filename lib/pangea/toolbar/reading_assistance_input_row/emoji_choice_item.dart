import 'package:fluffychat/config/app_config.dart';
import 'package:flutter/material.dart';

class EmojiChoiceItem extends StatefulWidget {
  const EmojiChoiceItem({
    super.key,
    this.topContent,
    this.textSize = 20,
    required this.content,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    required this.isSelected,
    this.contentOpacity = 1.0,
  });

  final String? topContent;
  final String content;
  final void Function() onTap;
  final void Function()? onDoubleTap;
  final void Function()? onLongPress;
  final bool isSelected;
  final double textSize;
  final double contentOpacity;

  @override
  _EmojiChoiceItemState createState() => _EmojiChoiceItemState();
}

class _EmojiChoiceItemState extends State<EmojiChoiceItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Align(
        alignment: Alignment.center,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? AppConfig.primaryColor.withAlpha((0.2 * 255).toInt())
                    : _isHovered
                        ? AppConfig.primaryColor.withAlpha((0.1 * 255).toInt())
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              ),
              child: Container(
                padding: const EdgeInsets.all(8.0),
                margin: const EdgeInsets.all(4.0),
                child: Column(
                  children: [
                    if (widget.topContent != null)
                      Opacity(
                        opacity: widget.contentOpacity,
                        child: Text(
                          widget.topContent!,
                          style: TextStyle(fontSize: widget.textSize + 4),
                        ),
                      ),
                    Text(
                      widget.content,
                      style: TextStyle(fontSize: widget.textSize - 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
