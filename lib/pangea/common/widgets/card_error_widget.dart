import 'package:flutter/material.dart';

import 'package:fluffychat/features/bot/utils/bot_style.dart';
import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';

class CardErrorWidget extends StatelessWidget {
  final String error;

  /// The failure behind this card, when the caller has it — a throttle
  /// replaces [error] per [rateLimitAwareCopy].
  final Object? cause;

  const CardErrorWidget(this.error, {this.cause, super.key});

  @override
  Widget build(BuildContext context) {
    final error = rateLimitAwareCopy(context, cause, this.error);
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
