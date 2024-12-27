import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/widgets/chat_list/analytics_summary/level_bar_popup.dart';
import 'package:fluffychat/pangea/widgets/pressable_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

class LevelBadge extends StatelessWidget {
  final int level;
  const LevelBadge({
    required this.level,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return PressableButton(
      color: Theme.of(context).colorScheme.surfaceBright,
      borderRadius: BorderRadius.circular(15),
      buttonHeight: 2.5,
      onPressed: () {
        showDialog<LevelBarPopup>(
          context: context,
          builder: (c) => const LevelBarPopup(),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: Theme.of(context).colorScheme.surfaceBright,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: AppConfig.gold,
              radius: 8,
              child: Icon(
                size: 12,
                Icons.star,
                color: Theme.of(context).colorScheme.surfaceBright,
                weight: 1000,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              L10n.of(context).levelShort(level),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
