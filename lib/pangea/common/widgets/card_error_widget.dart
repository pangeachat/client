import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';

class CardErrorWidget extends StatelessWidget {
  final String error;
  const CardErrorWidget(this.error, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        spacing: 6.0,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            L10n.of(context).oopsSomethingWentWrong,
            style: BotStyle.text(context),
            softWrap: true,
          ),
          Row(
            spacing: 12.0,
            mainAxisSize: MainAxisSize.min,
            children: [
              const BotFace(width: 50.0, expression: BotExpression.addled),
              Flexible(
                child: Text(
                  error,
                  style: BotStyle.text(context),
                  softWrap: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
