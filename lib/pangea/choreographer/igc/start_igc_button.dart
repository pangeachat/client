import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/choreographer/assistance_state_enum.dart';
import 'package:fluffychat/pangea/choreographer/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/choreographer_state_extension.dart';
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
  AnimationController? _spinController;
  late Animation<double> _rotation;

  AnimationController? _colorController;
  late Animation<Color?> _iconColor;
  late Animation<Color?> _backgroundColor;
  AssistanceStateEnum? _prevState;

  bool _shouldStop = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (_shouldStop) {
            _spinController?.stop();
            _spinController?.value = 0;
          } else {
            _spinController?.forward(from: 0);
          }
        }
      });

    _rotation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _spinController!,
        curve: Curves.linear,
      ),
    );

    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _prevState = widget.initialState;
    _iconColor = AlwaysStoppedAnimation(widget.initialForegroundColor);
    _backgroundColor = AlwaysStoppedAnimation(widget.initialBackgroundColor);
    _colorController!.forward(from: 0.0);

    widget.choreographer.addListener(_handleStateChange);
  }

  @override
  void dispose() {
    widget.choreographer.removeListener(_handleStateChange);
    _spinController?.dispose();
    _colorController?.dispose();
    super.dispose();
  }

  void _handleStateChange() {
    final prev = _prevState;
    final current = widget.choreographer.assistanceState;
    _prevState = current;

    if (!mounted || prev == current) return;
    final newIconColor = current.stateColor(context);
    final newBgColor = current.backgroundColor(context);
    final oldIconColor = _iconColor.value;
    final oldBgColor = _backgroundColor.value;

    // Create tweens from current → new colors
    _iconColor = ColorTween(
      begin: oldIconColor,
      end: newIconColor,
    ).animate(_colorController!);
    _backgroundColor = ColorTween(
      begin: oldBgColor,
      end: newBgColor,
    ).animate(_colorController!);
    _colorController!.forward(from: 0.0);

    if (current == AssistanceStateEnum.fetching) {
      _shouldStop = false;
      _spinController!.forward(from: 0.0);
    } else if (prev == AssistanceStateEnum.fetching) {
      _shouldStop = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_colorController == null || _spinController == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_colorController!, _spinController!]),
      builder: (context, child) {
        final enableFeedback =
            widget.choreographer.assistanceState.allowsFeedback;
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 40.0,
                    width: 40.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _backgroundColor.value,
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _rotation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _rotation.value * 2 * 3.14159,
                        child: child,
                      );
                    },
                    child: Icon(
                      Icons.autorenew_rounded,
                      size: 36,
                      color: _iconColor.value,
                    ),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _backgroundColor.value,
                    ),
                  ),
                  Icon(
                    size: 16,
                    Icons.check,
                    color: _iconColor.value,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
