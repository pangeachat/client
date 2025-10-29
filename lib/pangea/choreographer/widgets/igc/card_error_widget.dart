import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

class CardErrorWidget extends StatelessWidget {
  final String error;
  final double maxWidth;

  const CardErrorWidget({
    super.key,
    required this.error,
    this.maxWidth = 275,
  });

  @override
  Widget build(BuildContext context) {
    final ErrorCopy errorCopy = ErrorCopy(
      context,
      title: L10n.of(context).oopsSomethingWentWrong,
      body: error,
    );

    return Container(
      padding: const EdgeInsets.all(8.0),
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            errorCopy.title,
            style: BotStyle.text(context),
            softWrap: true,
          ),
          const SizedBox(height: 6.0),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BotFace(
                width: 50.0,
                expression: BotExpression.addled,
              ),
              const SizedBox(width: 12.0),
              Flexible(
                child: Text(
                  errorCopy.body,
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
