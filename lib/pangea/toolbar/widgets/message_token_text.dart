import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_linkify/flutter_linkify.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/common/utils/any_state_holder.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/utils/message_text_util.dart';
import 'package:fluffychat/pangea/message_token_text/message_token_button.dart';
import 'package:fluffychat/pangea/practice_activities/practice_selection.dart';
import 'package:fluffychat/pangea/practice_activities/practice_selection_repo.dart';
import 'package:fluffychat/pangea/toolbar/enums/message_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/widgets/message_selection_overlay.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Question - does this need to be stateful or does this work?
/// Need to test.
///

class MessageTokenText extends StatelessWidget {
  final PangeaMessageEvent _pangeaMessageEvent;
  final TextStyle _style;

  final bool Function(PangeaToken)? _isSelected;
  final void Function(PangeaToken)? _onClick;
  final bool Function(PangeaToken)? _isHighlighted;
  final MessageMode? _messageMode;
  final MessageOverlayController? _overlayController;
  final bool _isTransitionAnimation;

  const MessageTokenText({
    super.key,
    required PangeaMessageEvent pangeaMessageEvent,
    required List<PangeaToken>? tokens,
    required TextStyle style,
    required void Function(PangeaToken)? onClick,
    bool Function(PangeaToken)? isSelected,
    bool Function(PangeaToken)? isHighlighted,
    MessageMode? messageMode,
    MessageOverlayController? overlayController,
    bool isTransitionAnimation = false,
  })  : _onClick = onClick,
        _isSelected = isSelected,
        _style = style,
        _pangeaMessageEvent = pangeaMessageEvent,
        _messageMode = messageMode,
        _isHighlighted = isHighlighted,
        _overlayController = overlayController,
        _isTransitionAnimation = isTransitionAnimation;

  List<PangeaToken>? get _tokens =>
      _pangeaMessageEvent.messageDisplayRepresentation?.tokens;

  PracticeSelection? get messageAnalyticsEntry => _tokens != null
      ? PracticeSelectionRepo.get(
          _pangeaMessageEvent.messageDisplayLangCode,
          _tokens!,
        )
      : null;

  void callOnClick(TokenPosition tokenPosition) {
    _onClick != null && tokenPosition.token != null
        ? _onClick!(tokenPosition.token!)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_tokens == null) {
      return Text(
        _pangeaMessageEvent.messageDisplayText,
        style: _style,
      );
    }

    return MessageTextWidget(
      pangeaMessageEvent: _pangeaMessageEvent,
      existingStyle: _style,
      messageAnalyticsEntry: messageAnalyticsEntry,
      isSelected: _isSelected,
      onClick: callOnClick,
      messageMode: _messageMode,
      isHighlighted: _isHighlighted,
      overlayController: _overlayController,
      isTransitionAnimation: _isTransitionAnimation,
    );
  }
}

class HiddenText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const HiddenText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final textWidth = textPainter.size.width;
    final textHeight = textPainter.size.height;

    textPainter.dispose();

    return SizedBox(
      height: textHeight,
      child: Stack(
        children: [
          Container(
            width: textWidth,
            height: textHeight,
            color: Colors.transparent,
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: textWidth,
              height: 1,
              color: style.color,
            ),
          ),
        ],
      ),
    );
  }
}

class MessageTextWidget extends StatelessWidget {
  final PangeaMessageEvent pangeaMessageEvent;
  final TextStyle existingStyle;
  final PracticeSelection? messageAnalyticsEntry;
  final bool Function(PangeaToken)? isSelected;
  final void Function(TokenPosition tokenPosition)? onClick;
  final bool Function(PangeaToken)? isHighlighted;

  final bool? softWrap;
  final int? maxLines;
  final TextOverflow? overflow;
  final MessageMode? messageMode;

  final Animation<double>? contentSizeAnimation;
  final MessageOverlayController? overlayController;
  final bool isTransitionAnimation;
  final bool isMessage;

  const MessageTextWidget({
    super.key,
    required this.pangeaMessageEvent,
    required this.existingStyle,
    this.messageAnalyticsEntry,
    this.isSelected,
    this.onClick,
    this.softWrap,
    this.maxLines,
    this.overflow,
    this.messageMode,
    this.isHighlighted,
    this.contentSizeAnimation,
    this.overlayController,
    this.isTransitionAnimation = false,
    this.isMessage = true,
  });

  TextStyle style(BuildContext context) => !isMessage
      ? existingStyle
      : overlayController != null && overlayController!.maxWidth > 600
          ? existingStyle.copyWith(
              fontSize: Theme.of(context).textTheme.titleLarge?.fontSize,
            )
          : existingStyle.copyWith(
              fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize,
            );

  /// for some reason, this isn't the same as tokenTextWidth
  double tokenTextWidthForContainer(BuildContext context, PangeaToken token) {
    final textPainter = TextPainter(
      text: TextSpan(text: token.text.content, style: style(context)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final width = textPainter.width;
    textPainter.dispose();
    return width;
  }

  Color backgroundColor(BuildContext context, TokenPosition tokenPosition) {
    final hideTokenHighlights = messageAnalyticsEntry != null &&
        (messageAnalyticsEntry!.hasHiddenWordActivity ||
            messageAnalyticsEntry!.hasMessageMeaningActivity);

    Color backgroundColor = Colors.transparent;

    if (!hideTokenHighlights) {
      if (tokenPosition.selected) {
        backgroundColor = Theme.of(context).colorScheme.primary;
      }
      // else if (tokenPosition.isHighlighted) {
      //   backgroundColor = AppConfig.success.withAlpha(80);
      // }
    }
    return backgroundColor;
  }

  @override
  Widget build(BuildContext context) {
    final Characters messageCharacters =
        pangeaMessageEvent.messageDisplayText.characters;

    final tokenPositions = MessageTextUtil.getTokenPositions(
      pangeaMessageEvent,
      messageAnalyticsEntry: messageAnalyticsEntry,
      isSelected: isSelected,
      isHighlighted: isHighlighted,
    );

    if (tokenPositions == null) {
      return Text(
        pangeaMessageEvent.messageDisplayText,
        style: style(context),
        softWrap: softWrap,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final theme = Theme.of(context);
    final ownMessage =
        pangeaMessageEvent.senderId == Matrix.of(context).client.userID;
    final linkColor = theme.brightness == Brightness.light
        ? theme.colorScheme.primary
        : ownMessage
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface;

    return Text.rich(
      softWrap: softWrap ?? true,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      TextSpan(
        children:
            tokenPositions.mapIndexed((int i, TokenPosition tokenPosition) {
          final substring = messageCharacters
              .skip(tokenPosition.start)
              .take(tokenPosition.end - tokenPosition.start)
              .toString();

          if (tokenPosition.token?.pos == 'SPACE') {
            return const TextSpan(text: '\n');
          }

          if (tokenPosition.token != null) {
            // if the tokenPosition is a combination of the token and preceding / following punctuation
            // split them so that only the token itself is highlighted when clicked
            String start = '';
            String middle = '';
            String end = '';

            final startSplitIndex =
                tokenPosition.tokenStart - tokenPosition.start;
            final endSplitIndex = tokenPosition.tokenEnd - tokenPosition.start;

            start = substring.characters.take(startSplitIndex).toString();
            end = substring.characters.skip(endSplitIndex).toString();
            middle = substring.characters
                .skip(startSplitIndex)
                .take(endSplitIndex - startSplitIndex)
                .toString();

            final token = tokenPosition.token!;

            final tokenWidth = tokenTextWidthForContainer(context, token);

            return WidgetSpan(
              child: CompositedTransformTarget(
                link: overlayController == null || isTransitionAnimation
                    ? LayerLinkAndKey(token.hashCode.toString()).link
                    : MatrixState.pAnyState
                        .layerLinkAndKey(token.text.uniqueKey)
                        .link,
                child: Column(
                  key: overlayController == null || isTransitionAnimation
                      ? null
                      : MatrixState.pAnyState
                          .layerLinkAndKey(token.text.uniqueKey)
                          .key,
                  children: [
                    MessageTokenButton(
                      token: token,
                      overlayController: overlayController,
                      textStyle: style(context),
                      width: tokenWidth,
                      animate: isTransitionAnimation,
                      practiceTarget: overlayController
                                  ?.toolbarMode.associatedActivityType !=
                              null
                          ? overlayController?.practiceSelection
                              ?.activities(
                                overlayController!
                                    .toolbarMode.associatedActivityType!,
                              )
                              .firstWhereOrNull((a) => a.tokens.contains(token))
                          : null,
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: onClick != null
                            ? () => onClick?.call(tokenPosition)
                            : null,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (start.isNotEmpty)
                                LinkifySpan(
                                  text: start,
                                  style: style(context),
                                  linkStyle: TextStyle(
                                    decoration: TextDecoration.underline,
                                    color: linkColor,
                                  ),
                                  onOpen: (url) =>
                                      UrlLauncher(context, url.url).launchUrl(),
                                ),
                              tokenPosition.hideContent
                                  ? WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: GestureDetector(
                                        onTap: onClick != null
                                            ? () => onClick?.call(tokenPosition)
                                            : null,
                                        child: HiddenText(
                                          text: middle,
                                          style: style(context),
                                        ),
                                      ),
                                    )
                                  : LinkifySpan(
                                      text: middle,
                                      // style: style.merge(
                                      //   TextStyle(
                                      //     backgroundColor: backgroundColor(tokenPosition)
                                      //   ),
                                      // ),
                                      style: style(context),
                                      linkStyle: TextStyle(
                                        decoration: TextDecoration.underline,
                                        color: linkColor,
                                      ),
                                      onOpen: (url) =>
                                          UrlLauncher(context, url.url)
                                              .launchUrl(),
                                    ),
                              if (end.isNotEmpty)
                                LinkifySpan(
                                  text: end,
                                  style: style(context),
                                  linkStyle: TextStyle(
                                    decoration: TextDecoration.underline,
                                    color: linkColor,
                                  ),
                                  onOpen: (url) =>
                                      UrlLauncher(context, url.url).launchUrl(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(
                        milliseconds: AppConfig.overlayAnimationDuration,
                      ),
                      height:
                          overlayController != null && !isTransitionAnimation
                              ? 4
                              : 0,
                      width: tokenWidth,
                      child: Container(
                        color: backgroundColor(context, tokenPosition),
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else {
            if ((i > 0 || i < tokenPositions.length - 1) &&
                tokenPositions[i + 1].hideContent &&
                tokenPositions[i - 1].hideContent) {
              return WidgetSpan(
                child: GestureDetector(
                  onTap: onClick != null
                      ? () => onClick?.call(tokenPosition)
                      : null,
                  child: HiddenText(text: substring, style: style(context)),
                ),
              );
            }
            return LinkifySpan(
              text: substring,
              style: style(context),
              options: const LinkifyOptions(humanize: false),
              linkStyle: TextStyle(
                decoration: TextDecoration.underline,
                color: Theme.of(context).colorScheme.primary,
              ),
              onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
            );
          }
        }).toList(),
      ),
    );
  }
}
