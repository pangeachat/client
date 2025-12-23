import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/widgets/shrinkable_text.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class VocabAnalyticsListTile extends StatefulWidget {
  const VocabAnalyticsListTile({
    super.key,
    required this.constructId,
    this.level = ConstructLevelEnum.seeds,
    required this.textColor,
    this.onTap,
  });

  final void Function()? onTap;
  final ConstructIdentifier constructId;
  final ConstructLevelEnum level;
  final Color textColor;

  @override
  VocabAnalyticsListTileState createState() => VocabAnalyticsListTileState();
}

class VocabAnalyticsListTileState extends State<VocabAnalyticsListTile> {
  bool _isHovered = false;

  final double maxWidth = 100;
  final double padding = 8.0;

  @override
  Widget build(BuildContext context) {
    final analyticsService = Matrix.of(context).analyticsDataService;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          onTap: widget.onTap,
          child: Container(
            height: maxWidth,
            width: maxWidth,
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: _isHovered
                  ? widget.textColor.withAlpha(20)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StreamBuilder(
                  stream: analyticsService.updateDispatcher
                      .lemmaUpdateStream(widget.constructId),
                  builder: (context, snapshot) {
                    final emoji = snapshot.data?.emojis?.firstOrNull ??
                        widget.constructId.userSetEmoji;

                    return Container(
                      alignment: Alignment.center,
                      height: (maxWidth - padding * 2) * 0.6,
                      child: emoji != null
                          ? Text(
                              emoji,
                              style: const TextStyle(
                                fontSize: 22,
                              ),
                            )
                          : widget.level.icon(36.0),
                    );
                  },
                ),
                Container(
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 4),
                  height: (maxWidth - padding * 2) * 0.4,
                  child: ShrinkableText(
                    text: widget.constructId.lemma,
                    maxWidth: maxWidth - padding * 2,
                    style: TextStyle(
                      fontSize: 16,
                      color: widget.textColor,
                    ),
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
