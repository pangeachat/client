import 'dart:ui';

import 'package:flutter/material.dart';

class ChatViewBackground extends StatelessWidget {
  final ValueNotifier<bool> visible;
  const ChatViewBackground(this.visible, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: visible,
      builder: (context, value, _) {
        return value
            ? Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: Material(
                  borderOnForeground: false,
                  color: const Color.fromRGBO(0, 0, 0, 1).withAlpha(150),
                  clipBehavior: Clip.antiAlias,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                    child: Container(
                      height: double.infinity,
                      width: double.infinity,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink();
      },
    );
  }
}
