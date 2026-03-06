import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../bot/widgets/bot_face_svg.dart';

class CardHeader extends StatelessWidget {
  const CardHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12.0,
      children: [
        Expanded(
          child: Row(
            spacing: 12.0,
            children: [
              const BotFace(width: 50.0, expression: BotExpression.addled),
              Expanded(
                child: Text(
                  text,
                  style: BotStyle.text(context),
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_outlined),
          onPressed: MatrixState.pAnyState.closeOverlay,
        ),
      ],
    );
  }
}
