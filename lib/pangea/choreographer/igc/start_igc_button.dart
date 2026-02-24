import 'dart:math';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/choreographer/assistance_state_enum.dart';
import 'package:fluffychat/pangea/choreographer/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/choreographer_state_extension.dart';
import 'package:fluffychat/pangea/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/segmented_circular_progress.dart';
import 'package:fluffychat/pangea/learning_settings/settings_learning.dart';

class StartIGCButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Choreographer choreographer;
  final AssistanceStateEnum initialState;
  final Color initialForegroundColor;
  final Color initialBackgroundColor;

  const StartIGCButton({
    super.key,
    required this.onPressed,
    required this.choreographer,
    required this.initialState,
    required this.initialForegroundColor,
    required this.initialBackgroundColor,
  });

  @override
  State<StartIGCButton> createState() => _StartIGCButtonState();
}

class _StartIGCButtonState extends State<StartIGCButton>
    with TickerProviderStateMixin {
  late final AnimationController _spinController;
  late final Animation<double> _rotation;

  late final AnimationController _colorController;
  late Animation<Color?> _iconColor;
  late Animation<Color?> _backgroundColor;

  AssistanceStateEnum? _prevState;
  bool _shouldStop = false;

  @override
  void initState() {
    super.initState();

    _spinController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            if (_shouldStop) {
              _spinController.stop();
              _spinController.value = 0;
            } else {
              _spinController.forward(from: 0);
            }
          }
        });

    _rotation = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _spinController, curve: Curves.linear));

    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _prevState = widget.initialState;

    _iconColor = AlwaysStoppedAnimation(widget.initialForegroundColor);
    _backgroundColor = AlwaysStoppedAnimation(widget.initialBackgroundColor);

    _colorController.forward(from: 0.0);

    widget.choreographer.addListener(_handleStateChange);
  }

  @override
  void dispose() {
    widget.choreographer.removeListener(_handleStateChange);
    _spinController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  void _handleStateChange() {
    final prev = _prevState;
    final current = widget.choreographer.assistanceState;
    _prevState = current;

    if (!mounted || prev == current) return;

    final newIconColor = current.stateColor(context);
    final newBgColor = current.backgroundColor(context);

    _iconColor = ColorTween(
      begin: _iconColor.value,
      end: newIconColor,
    ).animate(_colorController);

    _backgroundColor = ColorTween(
      begin: _backgroundColor.value,
      end: newBgColor,
    ).animate(_colorController);

    _colorController.forward(from: 0.0);

    if (current == AssistanceStateEnum.fetching) {
      _shouldStop = false;
      _spinController.forward(from: 0.0);
    } else if (prev == AssistanceStateEnum.fetching) {
      _shouldStop = true;
    }

    setState(() {}); // triggers AnimatedSwitcher change
  }

  @override
  Widget build(BuildContext context) {
    final enableFeedback = widget.choreographer.assistanceState.allowsFeedback;

    return AnimatedBuilder(
      animation: _colorController, // 🔥 only color animates parent
      builder: (context, _) {
        return Tooltip(
          message: enableFeedback ? L10n.of(context).check : "",
          child: Material(
            elevation: enableFeedback ? 4.0 : 0.0,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            shadowColor: Theme.of(context).colorScheme.surface.withAlpha(128),
            child: InkWell(
              enableFeedback: enableFeedback,
              customBorder: const CircleBorder(),
              onTap: enableFeedback ? widget.onPressed : null,
              onLongPress: enableFeedback
                  ? () => showDialog(
                      context: context,
                      builder: (c) => const SettingsLearning(),
                      barrierDismissible: false,
                    )
                  : null,
              child: SizedBox(
                width: 40,
                height: 40,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [...previousChildren, ?currentChild],
                    );
                  },
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    );
                  },
                  child:
                      widget.choreographer.assistanceState ==
                          AssistanceStateEnum.fetched
                      ? _IGCLoaded(widget.choreographer)
                      : _IGCLoading(
                          backgroundColor: _backgroundColor.value,
                          iconColor: _iconColor.value,
                          rotation: _rotation,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IGCLoading extends StatelessWidget {
  final Color? backgroundColor;
  final Color? iconColor;
  final Animation<double> rotation;

  const _IGCLoading({
    required this.backgroundColor,
    required this.iconColor,
    required this.rotation,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('loader'),
      alignment: Alignment.center,
      children: [
        Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: backgroundColor,
          ),
        ),
        AnimatedBuilder(
          animation: rotation,
          builder: (context, child) {
            return Transform.rotate(
              angle: rotation.value * 2 * pi,
              child: child,
            );
          },
          child: Icon(Icons.autorenew_rounded, size: 36, color: iconColor),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: backgroundColor,
          ),
        ),
        Icon(Icons.check, size: 16, color: iconColor),
      ],
    );
  }
}

class _IGCLoaded extends StatelessWidget {
  final Choreographer choreographer;
  const _IGCLoaded(this.choreographer);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('segments'),
      width: 36,
      height: 36,
      child: StreamBuilder(
        stream: choreographer.igcController.matchUpdateStream.stream,
        builder: (context, _) => ValueListenableBuilder(
          valueListenable: choreographer.igcController.activeMatch,
          builder: (context, activeMatch, _) {
            final matches = choreographer.igcController.sortedMatches;
            if (matches.isEmpty) {
              return SegmentedCircularProgress(
                segments: [Segment(100, AppConfig.success)],
              );
            }

            final segmentPercent = 100 / matches.length;
            return SegmentedCircularProgress(
              segments: matches.map((m) {
                final isActiveMatch =
                    m.originalMatch.match.offset ==
                        activeMatch?.originalMatch.match.offset &&
                    m.originalMatch.match.length ==
                        activeMatch?.originalMatch.match.length;

                final opacity = isActiveMatch
                    ? 1.0
                    : m.updatedMatch.status.igcButtonOpacity;

                return Segment(
                  segmentPercent,
                  m.updatedMatch.status.isOpen
                      ? m.updatedMatch.match.type.color
                      : AppConfig.success,
                  opacity: opacity,
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
