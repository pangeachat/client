import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ChatBannerBuilder extends StatefulWidget {
  final String overlayKey;
  final Completer<void> closeCompleter;
  final Widget Function(
    BuildContext context,
    BoxConstraints constraints,
    VoidCallback close,
  )
  builder;

  final VoidCallback? onTap;
  final VoidCallback? onAnimatedIn;

  const ChatBannerBuilder({
    required this.overlayKey,
    required this.closeCompleter,
    required this.builder,
    this.onTap,
    this.onAnimatedIn,
    super.key,
  });

  @override
  State<ChatBannerBuilder> createState() => _ChatBannerBuilderState();
}

class _ChatBannerBuilderState extends State<ChatBannerBuilder>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _animation;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: FluffyThemes.animationDuration,
      vsync: this,
    );

    _animation = CurvedAnimation(parent: _controller!, curve: Curves.easeInOut);
    _controller!.forward().then((_) {
      widget.onAnimatedIn?.call();
      _autoCloseTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) _close();
      });
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    if (!widget.closeCompleter.isCompleted) {
      widget.closeCompleter.complete();
    }
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_controller?.status == AnimationStatus.completed) {
      await _controller?.reverse();
    }
    MatrixState.pAnyState.closeOverlay(widget.overlayKey);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: SizeTransition(
          sizeFactor: _animation!,
          axisAlignment: -1.0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onPanUpdate: (details) {
                  if (details.delta.dy < -10) _close();
                },
                onTap: widget.onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16.0,
                    horizontal: 4.0,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: AppConfig.gold.withAlpha(200),
                        width: 2.0,
                      ),
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(AppConfig.borderRadius),
                      bottomRight: Radius.circular(AppConfig.borderRadius),
                    ),
                  ),
                  child: widget.builder(context, constraints, _close),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
