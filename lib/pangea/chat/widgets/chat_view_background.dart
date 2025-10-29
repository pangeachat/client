import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choreographer_state_extension.dart';

class ChatViewBackground extends StatelessWidget {
  final Choreographer choreographer;
  const ChatViewBackground(this.choreographer, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: choreographer,
      builder: (context, _) {
        return choreographer.isITOpen
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
