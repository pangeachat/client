import 'package:flutter/material.dart';

import 'package:flutter_linkify/flutter_linkify.dart';

import 'package:fluffychat/utils/url_launcher.dart';

class UnderlineText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextStyle? linkStyle;
  final TextDirection? textDirection;
  final Color? underlineColor;

  const UnderlineText({
    super.key,
    required this.text,
    required this.style,
    this.linkStyle,
    this.textDirection,
    this.underlineColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomLeft,
      children: [
        RichText(
          textDirection: textDirection,
          text: TextSpan(
            children: [
              LinkifySpan(
                text: text,
                style: style,
                linkStyle: linkStyle,
                onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 3,
            color: underlineColor ?? Colors.transparent,
          ),
        ),
      ],
    );
  }
}
