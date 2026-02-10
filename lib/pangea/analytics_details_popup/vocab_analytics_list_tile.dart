import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/widgets/shrinkable_text.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

class VocabAnalyticsListTile extends StatelessWidget {
  final void Function()? onTap;
  final ConstructIdentifier constructId;
  final ConstructLevelEnum level;
  final Color textColor;
  final bool selected;

  const VocabAnalyticsListTile({
    super.key,
    required this.constructId,
    this.level = ConstructLevelEnum.seeds,
    required this.textColor,
    this.onTap,
    this.selected = false,
  });

  final double maxWidth = 100;
  final double padding = 8.0;

  @override
  Widget build(BuildContext context) {
    final analyticsService = Matrix.of(context).analyticsDataService;
    return HoverBuilder(
      builder: (context, hovered) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          onTap: onTap,
          child: Container(
            height: maxWidth,
            width: maxWidth,
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: hovered || selected
                  ? textColor.withAlpha(20)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StreamBuilder(
                  stream: analyticsService.updateDispatcher.lemmaUpdateStream(
                    constructId,
                  ),
                  builder: (context, snapshot) {
                    final emoji = snapshot.data?.emojis?.firstOrNull ??
                        constructId.userSetEmoji;

                    return Container(
                      alignment: Alignment.center,
                      height: (maxWidth - padding * 2) * 0.6,
                      child: emoji != null
                          ? Text(emoji, style: const TextStyle(fontSize: 22))
                          : Text(
                              "-",
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: textColor.withAlpha(100),
                              ),
                            ),
                    );
                  },
                ),
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.only(top: 4),
                  height: (maxWidth - padding * 2) * 0.4,
                  child: ShrinkableText(
                    text: constructId.lemma,
                    maxWidth: maxWidth - padding * 2,
                    style: TextStyle(fontSize: 16, color: textColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
