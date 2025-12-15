import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/widgets/shrinkable_text.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';

class VocabAnalyticsListTile extends StatefulWidget {
  const VocabAnalyticsListTile({
    super.key,
    required this.emoji,
    required this.constructId,
    required this.textColor,
    required this.icon,
    this.onTap,
  });

  final String? emoji;
  final void Function()? onTap;
  final ConstructIdentifier constructId;
  final Color textColor;
  final Widget icon;

  @override
  VocabAnalyticsListTileState createState() => VocabAnalyticsListTileState();
}

class VocabAnalyticsListTileState extends State<VocabAnalyticsListTile> {
  bool _isHovered = false;

  final double maxWidth = 100;
  final double padding = 8.0;

  @override
  Widget build(BuildContext context) {
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
                Container(
                  alignment: Alignment.center,
                  height: (maxWidth - padding * 2) * 0.6,
                  child: widget.icon,
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
