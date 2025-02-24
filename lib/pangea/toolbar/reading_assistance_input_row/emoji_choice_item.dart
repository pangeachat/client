import 'package:fluffychat/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class EmojiChoiceItem extends StatelessWidget {
  const EmojiChoiceItem({
    super.key,
    required this.content,
    required this.onTap,
    required this.isSelected,
  });

  final String content;
  final void Function() onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: kIsWeb ? 56 : 48,
        height: AppConfig.defaultFooterHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppConfig.success.withAlpha((0.2 * 255).toInt())
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          content,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
