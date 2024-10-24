import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/utils/bot_style.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:fluffychat/pangea/widgets/common/bot_face_svg.dart';
import 'package:fluffychat/pangea/widgets/igc/card_header.dart';
import 'package:flutter/material.dart';

class CardErrorWidget extends StatelessWidget {
  final Object? error;
  final Choreographer? choreographer;
  final int? offset;
  final double? maxWidth;

  const CardErrorWidget({
    super.key,
    this.error,
    this.choreographer,
    this.offset,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final ErrorCopy errorCopy = ErrorCopy(context, error);

    return ConstrainedBox(
      constraints: maxWidth != null
          ? BoxConstraints(maxWidth: maxWidth!)
          : const BoxConstraints(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CardHeader(
              text: errorCopy.title,
              botExpression: BotExpression.addled,
              onClose: () => choreographer?.onMatchError(
                cursorOffset: offset,
              ),
            ),
            const SizedBox(height: 12.0),
            Text(
              errorCopy.body,
              style: BotStyle.text(context),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
