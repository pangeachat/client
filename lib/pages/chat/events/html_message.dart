import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/shades-of-purple.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:linkify/linkify.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/toolbar/enums/activity_type_enum.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import '../../../utils/url_launcher.dart';

class HtmlMessage extends StatelessWidget {
  final String html;
  final Room room;
  final Color textColor;
  // #Pangea
  final bool isOverlay;
  final PangeaMessageEvent? pangeaMessageEvent;
  final ChatController controller;
  final Event event;
  final Event? nextEvent;
  final Event? prevEvent;

  final bool Function(PangeaToken)? isSelected;
  final void Function(PangeaToken)? onClick;
  // Pangea#

  const HtmlMessage({
    super.key,
    required this.html,
    required this.room,
    this.textColor = Colors.black,
    // #Pangea
    required this.isOverlay,
    required this.event,
    this.pangeaMessageEvent,
    required this.controller,
    this.nextEvent,
    this.prevEvent,
    this.isSelected,
    this.onClick,
    // Pangea#
  });

  dom.Node _linkifyHtml(dom.Node element) {
    for (final node in element.nodes) {
      if (node is! dom.Text ||
          (element is dom.Element && element.localName == 'code')) {
        node.replaceWith(_linkifyHtml(node));
        continue;
      }

      final parts = linkify(
        node.text,
        options: const LinkifyOptions(humanize: false),
      );

      if (!parts.any((part) => part is UrlElement)) {
        continue;
      }

      final newHtml = parts
          .map(
            (linkifyElement) => linkifyElement is! UrlElement
                ? linkifyElement.text.replaceAll('<', '&#60;')
                : '<a href="${linkifyElement.text}">${linkifyElement.text}</a>',
          )
          .join(' ');

      node.replaceWith(dom.Element.html('<p>$newHtml</p>'));
    }
    return element;
  }

  // #Pangea
  List<PangeaToken>? get tokens =>
      pangeaMessageEvent?.messageDisplayRepresentation?.tokens;

  PangeaToken? getToken(
    String text,
    int offset,
    int length,
  ) =>
      tokens?.firstWhereOrNull(
        (token) => token.text.offset == offset && token.text.length == length,
      );

  /// Wrap token spans in token tags so styling / functions can be applied
  dom.Node _tokenizeHtml(
    dom.Node element,
    String fullHtml,
    List<PangeaToken> remainingTokens,
  ) {
    for (final node in element.nodes) {
      node.replaceWith(_tokenizeHtml(node, fullHtml, remainingTokens));
    }

    if (element is dom.Text) {
      // once a text element in reached in the HTML tree, find and
      // wrap all the spans with matching tokens until all tokens
      // have been wrapped or no more text elements remain
      String tokenizedText = element.text;
      while (remainingTokens.isNotEmpty) {
        final tokenText = remainingTokens.first.text.content;

        int startIndex = tokenizedText.lastIndexOf('</token>');
        startIndex = startIndex == -1 ? 0 : startIndex + 8;
        final int tokenIndex = tokenizedText.indexOf(
          tokenText,
          startIndex,
        );

        // if the token is not found in the text, check if the token exist in the full HTML.
        // If not, remove the token and continue. If so, break to move on to the next node in the HTML.
        if (tokenIndex == -1) {
          final fullHtmlIndex = fullHtml.indexOf(tokenText);
          if (fullHtmlIndex == -1) {
            remainingTokens.removeAt(0);
            continue;
          } else {
            break;
          }
        }

        final token = remainingTokens.removeAt(0);
        final tokenEnd = tokenIndex + tokenText.length;
        final before = tokenizedText.substring(0, tokenIndex);
        final after = tokenizedText.substring(tokenEnd);

        tokenizedText =
            "$before<token offset=\"${token.text.offset}\" length=\"${token.text.length}\">$tokenText</token>$after";
      }

      final newElement = dom.Element.html('<span>$tokenizedText</span>');
      return newElement;
    }

    return element;
  }
  // Pangea#

  @override
  Widget build(BuildContext context) {
    final fontSize = AppConfig.messageFontSize * AppConfig.fontSizeFactor;

    final linkColor = textColor.withAlpha(150);

    final blockquoteStyle = Style(
      border: Border(
        left: BorderSide(
          width: 3,
          color: textColor,
        ),
      ),
      padding: HtmlPaddings.only(left: 6, bottom: 0),
    );

    // #Pangea
    // final element = _linkifyHtml(HtmlParser.parseHTML(html));
    dom.Node element = _linkifyHtml(HtmlParser.parseHTML(html));
    if (tokens != null && element is dom.Element) {
      try {
        element = _tokenizeHtml(element, element.innerHtml, List.from(tokens!));
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {
            'html': html,
            'tokens': tokens,
          },
        );
      }
    }
    // Pangea#

    // there is no need to pre-validate the html, as we validate it while rendering
    // #Pangea
    return SelectionArea(
      child: GestureDetector(
        onTap: () {
          if (!isOverlay) {
            controller.showToolbar(
              event,
              pangeaMessageEvent: pangeaMessageEvent,
              nextEvent: nextEvent,
              prevEvent: prevEvent,
            );
          }
        },
        // Pangea#
        child: Html.fromElement(
          documentElement: element as dom.Element,
          style: {
            '*': Style(
              color: textColor,
              margin: Margins.all(0),
              fontSize: FontSize(fontSize),
            ),
            'a': Style(color: linkColor, textDecorationColor: linkColor),
            'h1': Style(
              fontSize: FontSize(fontSize * 2),
              lineHeight: LineHeight.number(1.5),
              fontWeight: FontWeight.w600,
            ),
            'h2': Style(
              fontSize: FontSize(fontSize * 1.75),
              lineHeight: LineHeight.number(1.5),
              fontWeight: FontWeight.w500,
            ),
            'h3': Style(
              fontSize: FontSize(fontSize * 1.5),
              lineHeight: LineHeight.number(1.5),
            ),
            'h4': Style(
              fontSize: FontSize(fontSize * 1.25),
              lineHeight: LineHeight.number(1.5),
            ),
            'h5': Style(
              fontSize: FontSize(fontSize * 1.25),
              lineHeight: LineHeight.number(1.5),
            ),
            'h6': Style(
              fontSize: FontSize(fontSize),
              lineHeight: LineHeight.number(1.5),
            ),
            'blockquote': blockquoteStyle,
            'tg-forward': blockquoteStyle,
            'hr': Style(
              border: Border.all(color: textColor, width: 0.5),
            ),
            'table': Style(
              border: Border.all(color: textColor, width: 0.5),
            ),
            'tr': Style(
              border: Border.all(color: textColor, width: 0.5),
            ),
            'td': Style(
              border: Border.all(color: textColor, width: 0.5),
              padding: HtmlPaddings.all(2),
            ),
            'th': Style(
              border: Border.all(color: textColor, width: 0.5),
            ),
          },
          extensions: [
            RoomPillExtension(context, room, fontSize, linkColor),
            CodeExtension(fontSize: fontSize),
            // #Pangea
            // const TableHtmlExtension(),
            // Pangea#
            SpoilerExtension(textColor: textColor),
            const ImageExtension(),
            FontColorExtension(),
            FallbackTextExtension(fontSize: fontSize),
            // #Pangea
            if (pangeaMessageEvent != null)
              TokenExtension(
                style: AppConfig.messageTextStyle(
                  pangeaMessageEvent!.event,
                  textColor,
                ),
                getToken: getToken,
                isSelected: isSelected,
                onClick: onClick,
              ),
            // Pangea#
          ],
          onLinkTap: (url, _, element) => UrlLauncher(
            context,
            url,
            element?.text,
          ).launchUrl(),
          onlyRenderTheseTags: const {
            ...allowedHtmlTags,
            // Needed to make it work properly
            'body',
            'html',
          },
          shrinkWrap: true,
        ),
      ),
    );
  }

  static const Set<String> fallbackTextTags = {'tg-forward'};

  /// Keep in sync with: https://spec.matrix.org/v1.6/client-server-api/#mroommessage-msgtypes
  static const Set<String> allowedHtmlTags = {
    'font',
    'del',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'p',
    'a',
    'ul',
    'ol',
    'sup',
    'sub',
    'li',
    'b',
    'i',
    'u',
    'strong',
    'em',
    'strike',
    'code',
    'hr',
    'br',
    'div',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    'caption',
    'pre',
    'span',
    'img',
    'details',
    'summary',
    // Not in the allowlist of the matrix spec yet but should be harmless:
    'ruby',
    'rp',
    'rt',
    // Workaround for https://github.com/krille-chan/fluffychat/issues/507
    ...fallbackTextTags,
    // #Pangea
    'token',
    // Pangea#
  };
}

// #Pangea
class TokenExtension extends HtmlExtension {
  final TextStyle style;
  final PangeaToken? Function(String, int, int) getToken;
  final bool Function(PangeaToken)? isSelected;
  final void Function(PangeaToken)? onClick;

  const TokenExtension({
    required this.style,
    required this.getToken,
    this.isSelected,
    this.onClick,
  });

  @override
  Set<String> get supportedTags => {'token'};

  @override
  InlineSpan build(ExtensionContext context) {
    final token = getToken(
      context.attributes['offset'] ?? '',
      int.tryParse(context.attributes['offset'] ?? '') ?? 0,
      int.tryParse(context.attributes['length'] ?? '') ?? 0,
    );

    final selected =
        token != null && isSelected != null ? isSelected!.call(token) : false;

    final shouldDo = token?.shouldDoActivity(
          a: ActivityTypeEnum.wordMeaning,
          feature: null,
          tag: null,
        ) ??
        false;

    final didMeaningActivity = token?.didActivitySuccessfully(
          ActivityTypeEnum.wordMeaning,
        ) ??
        true;

    Color backgroundColor = Colors.transparent;
    if (selected) {
      backgroundColor = AppConfig.primaryColor.withAlpha(80);
    } else if (isSelected != null && shouldDo) {
      backgroundColor = !didMeaningActivity
          ? AppConfig.success.withAlpha(60)
          : AppConfig.gold.withAlpha(60);
    }

    return TextSpan(
      recognizer: TapGestureRecognizer()
        ..onTap = onClick != null && token != null
            ? () => onClick?.call(token)
            : null,
      text: context.innerHtml,
      style: style.merge(TextStyle(backgroundColor: backgroundColor)),
    );
  }
}
// Pangea#

class FontColorExtension extends HtmlExtension {
  static const String colorAttribute = 'color';
  static const String mxColorAttribute = 'data-mx-color';
  static const String bgColorAttribute = 'data-mx-bg-color';

  @override
  Set<String> get supportedTags => {'font', 'span'};

  @override
  bool matches(ExtensionContext context) {
    if (!supportedTags.contains(context.elementName)) return false;
    return context.element?.attributes.keys.any(
          {
            colorAttribute,
            mxColorAttribute,
            bgColorAttribute,
          }.contains,
        ) ??
        false;
  }

  Color? hexToColor(String? hexCode) {
    if (hexCode == null) return null;
    if (hexCode.startsWith('#')) hexCode = hexCode.substring(1);
    if (hexCode.length == 6) hexCode = 'FF$hexCode';
    final colorValue = int.tryParse(hexCode, radix: 16);
    return colorValue == null ? null : Color(colorValue);
  }

  @override
  InlineSpan build(
    ExtensionContext context,
  ) {
    final colorText = context.element?.attributes[colorAttribute] ??
        context.element?.attributes[mxColorAttribute];
    final bgColor = context.element?.attributes[bgColorAttribute];
    return TextSpan(
      style: TextStyle(
        color: hexToColor(colorText),
        backgroundColor: hexToColor(bgColor),
      ),
      text: context.innerHtml,
    );
  }
}

class ImageExtension extends HtmlExtension {
  final double defaultDimension;

  const ImageExtension({this.defaultDimension = 64});

  @override
  Set<String> get supportedTags => {'img'};

  @override
  InlineSpan build(ExtensionContext context) {
    final mxcUrl = Uri.tryParse(context.attributes['src'] ?? '');
    if (mxcUrl == null || mxcUrl.scheme != 'mxc') {
      return TextSpan(text: context.attributes['alt']);
    }

    final width = double.tryParse(context.attributes['width'] ?? '');
    final height = double.tryParse(context.attributes['height'] ?? '');

    final actualWidth = width ?? height ?? defaultDimension;
    final actualHeight = height ?? width ?? defaultDimension;

    return WidgetSpan(
      child: SizedBox(
        width: actualWidth,
        height: actualHeight,
        child: MxcImage(
          uri: mxcUrl,
          width: actualWidth,
          height: actualHeight,
          isThumbnail: (actualWidth * actualHeight) > (256 * 256),
        ),
      ),
    );
  }
}

class SpoilerExtension extends HtmlExtension {
  final Color textColor;

  const SpoilerExtension({required this.textColor});

  @override
  Set<String> get supportedTags => {'span'};

  static const String customDataAttribute = 'data-mx-spoiler';

  @override
  bool matches(ExtensionContext context) {
    if (context.elementName != 'span') return false;
    return context.element?.attributes.containsKey(customDataAttribute) ??
        false;
  }

  @override
  InlineSpan build(ExtensionContext context) {
    var obscure = true;
    final children = context.inlineSpanChildren;
    return WidgetSpan(
      child: StatefulBuilder(
        builder: (context, setState) {
          return InkWell(
            onTap: () => setState(() {
              obscure = !obscure;
            }),
            child: RichText(
              text: TextSpan(
                style: obscure ? TextStyle(backgroundColor: textColor) : null,
                children: children,
              ),
            ),
          );
        },
      ),
    );
  }
}

class CodeExtension extends HtmlExtension {
  final double fontSize;

  CodeExtension({required this.fontSize});
  @override
  Set<String> get supportedTags => {'code'};

  @override
  InlineSpan build(ExtensionContext context) => WidgetSpan(
        child: Material(
          clipBehavior: Clip.hardEdge,
          borderRadius: BorderRadius.circular(4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              context.element?.text ?? '',
              language: context.element?.className
                      .split(' ')
                      .singleWhereOrNull(
                        (className) => className.startsWith('language-'),
                      )
                      ?.split('language-')
                      .last ??
                  'md',
              theme: shadesOfPurpleTheme,
              padding: EdgeInsets.symmetric(
                horizontal: 6,
                vertical: context.element?.parent?.localName == 'pre' ? 6 : 0,
              ),
              textStyle: TextStyle(fontSize: fontSize),
            ),
          ),
        ),
      );
}

class FallbackTextExtension extends HtmlExtension {
  final double fontSize;

  FallbackTextExtension({required this.fontSize});
  @override
  Set<String> get supportedTags => HtmlMessage.fallbackTextTags;

  @override
  InlineSpan build(ExtensionContext context) => TextSpan(
        text: context.element?.text ?? '',
        style: TextStyle(
          fontSize: fontSize,
        ),
      );
}

class RoomPillExtension extends HtmlExtension {
  final Room room;
  final BuildContext context;
  final double fontSize;
  final Color color;

  RoomPillExtension(this.context, this.room, this.fontSize, this.color);
  @override
  Set<String> get supportedTags => {'a'};

  @override
  bool matches(ExtensionContext context) {
    if (context.elementName != 'a') return false;
    final userId = context.element?.attributes['href']
        ?.parseIdentifierIntoParts()
        ?.primaryIdentifier;
    return userId != null;
  }

  static final _cachedUsers = <String, User?>{};

  Future<User?> _fetchUser(String matrixId) async =>
      _cachedUsers[room.id + matrixId] ??= await room.requestUser(matrixId);

  @override
  InlineSpan build(ExtensionContext context) {
    final href = context.element?.attributes['href'];
    final matrixId = href?.parseIdentifierIntoParts()?.primaryIdentifier;
    if (href == null || matrixId == null) {
      return TextSpan(text: context.innerHtml);
    }
    if (matrixId.sigil == '@') {
      return WidgetSpan(
        child: FutureBuilder<User?>(
          future: _fetchUser(matrixId),
          builder: (context, snapshot) => MatrixPill(
            key: Key('user_pill_$matrixId'),
            name: _cachedUsers[room.id + matrixId]?.calcDisplayname() ??
                matrixId.localpart ??
                matrixId,
            avatar: _cachedUsers[room.id + matrixId]?.avatarUrl,
            uri: href,
            outerContext: this.context,
            fontSize: fontSize,
            color: color,
          ),
        ),
      );
    }
    if (matrixId.sigil == '#' || matrixId.sigil == '!') {
      final room = matrixId.sigil == '!'
          ? this.room.client.getRoomById(matrixId)
          : this.room.client.getRoomByAlias(matrixId);
      if (room != null) {
        return WidgetSpan(
          child: MatrixPill(
            name: room.getLocalizedDisplayname(),
            avatar: room.avatar,
            uri: href,
            outerContext: this.context,
            fontSize: fontSize,
            color: color,
          ),
        );
      }
    }

    return TextSpan(text: context.innerHtml);
  }
}

class MatrixPill extends StatelessWidget {
  final String name;
  final BuildContext outerContext;
  final Uri? avatar;
  final String uri;
  final double? fontSize;
  final Color? color;

  const MatrixPill({
    super.key,
    required this.name,
    required this.outerContext,
    this.avatar,
    required this.uri,
    required this.fontSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: UrlLauncher(outerContext, uri).launchUrl,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(
            mxContent: avatar,
            name: name,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              color: color,
              decorationColor: color,
              decoration: TextDecoration.underline,
              fontSize: fontSize,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
