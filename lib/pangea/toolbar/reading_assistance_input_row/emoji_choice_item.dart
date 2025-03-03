import 'package:fluffychat/config/app_config.dart';
import 'package:flutter/material.dart';

class EmojiChoiceItem extends StatelessWidget {
  const EmojiChoiceItem({
    super.key,
    this.topContent,
    this.textSize = 24,
    required this.content,
    required this.onTap,
    required this.isSelected,
  });

  final String? topContent;
  final String content;
  final void Function() onTap;
  final bool isSelected;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        // width: kIsWeb ? 56 : 48,
        // height: AppConfig.defaultFooterHeight + 30,
        alignment: Alignment.bottomCenter,
        decoration: BoxDecoration(
          color: isSelected
              ? AppConfig.success.withAlpha((0.2 * 255).toInt())
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              if (topContent != null)
                Text(
                  // "hey",
                  topContent!,
                  style: TextStyle(fontSize: textSize),
                ),
              Text(
                content,
                style: TextStyle(fontSize: textSize),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
