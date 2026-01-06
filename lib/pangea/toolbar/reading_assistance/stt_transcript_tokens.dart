import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/speech_to_text/speech_to_text_response_model.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/token_rendering_util.dart';
import 'package:fluffychat/pangea/toolbar/reading_assistance/tokens_util.dart';
import 'package:fluffychat/widgets/hover_builder.dart';

class SttTranscriptTokens extends StatelessWidget {
  final String eventId;
  final SpeechToTextResponseModel model;
  final TextStyle? style;

  final void Function(PangeaToken)? onClick;
  final bool Function(PangeaToken)? isSelected;

  const SttTranscriptTokens({
    super.key,
    required this.eventId,
    required this.model,
    this.onClick,
    this.isSelected,
    this.style,
  });

  List<PangeaToken> get tokens =>
      model.transcript.sttTokens.map((t) => t.token).toList();

  @override
  Widget build(BuildContext context) {
    debugPrint("Tokens: ${tokens.map((t) => t.toJson())}");
    if (model.transcript.sttTokens.isEmpty) {
      return Text(
        model.transcript.text,
        style: style ?? DefaultTextStyle.of(context).style,
        textScaler: TextScaler.noScaling,
      );
    }

    final messageCharacters = model.transcript.text.characters;
    final renderer = TokenRenderingUtil(
      existingStyle: (style ?? DefaultTextStyle.of(context).style),
    );

    final newTokens = TokensUtil.getNewTokens(
      eventId,
      tokens,
      model.langCode,
    );

    return RichText(
      textScaler: TextScaler.noScaling,
      text: TextSpan(
        style: style ?? DefaultTextStyle.of(context).style,
        children:
            TokensUtil.getGlobalTokenPositions(tokens).map((tokenPosition) {
          final text = messageCharacters
              .skip(tokenPosition.startIndex)
              .take(tokenPosition.endIndex - tokenPosition.startIndex)
              .toString();

          if (tokenPosition.token == null) {
            return TextSpan(
              text: text,
              style: style ?? DefaultTextStyle.of(context).style,
            );
          }

          final token = tokenPosition.token!;
          final selected = isSelected?.call(token) ?? false;

          return WidgetSpan(
            child: HoverBuilder(
              builder: (context, hovered) => MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: onClick != null ? () => onClick?.call(token) : null,
                  child: RichText(
                    text: TextSpan(
                      text: text,
                      style: renderer.style(
                        underlineColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withAlpha(200),
                        hovered: hovered,
                        selected: selected,
                        isNew: newTokens.any((t) => t == token.text),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
