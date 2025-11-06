import 'dart:async';
import 'dart:math' as math;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/choreographer/assistance_state_enum.dart';
import 'package:fluffychat/pangea/choreographer/choreographer_state_extension.dart';
import 'package:fluffychat/pangea/learning_settings/pages/settings_learning.dart';
import 'package:flutter/material.dart';

import '../../../pages/chat/chat.dart';

class StartIGCButton extends StatefulWidget {
  const StartIGCButton({
    super.key,
    required this.controller,
  });

  final ChatController controller;

  @override
  State<StartIGCButton> createState() => StartIGCButtonState();
}

class StartIGCButtonState extends State<StartIGCButton>
    with SingleTickerProviderStateMixin {
  AssistanceStateEnum get assistanceState =>
      widget.controller.choreographer.assistanceState;
  AnimationController? _controller;
  AssistanceStateEnum? _prevState;

  @override
  void initState() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    widget.controller.choreographer.addListener(_updateSpinnerState);
    super.initState();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _updateSpinnerState() {
    if (_prevState != AssistanceStateEnum.fetching &&
        assistanceState == AssistanceStateEnum.fetching) {
      _controller?.repeat();
    } else if (_prevState == AssistanceStateEnum.fetching &&
        assistanceState != AssistanceStateEnum.fetching) {
      _controller?.reset();
    }
    if (mounted) {
      setState(() => _prevState = assistanceState);
    }
  }

  bool get _enableFeedback {
    return ![
      AssistanceStateEnum.fetching,
      AssistanceStateEnum.fetched,
      AssistanceStateEnum.complete,
      AssistanceStateEnum.noMessage,
      AssistanceStateEnum.noSub,
      AssistanceStateEnum.error,
    ].contains(assistanceState);
  }

  Future<void> _onTap() async {
    if (!_enableFeedback) return;
    if (widget.controller.shouldShowLanguageMismatchPopup) {
      widget.controller.showLanguageMismatchPopup();
    } else {
      await widget.controller.choreographer.requestLanguageAssistance();
      final openMatch =
          widget.controller.choreographer.igcController.firstOpenMatch;
      widget.controller.onSelectMatch(openMatch);
    }
  }

  Color get _backgroundColor {
    switch (assistanceState) {
      case AssistanceStateEnum.noSub:
      case AssistanceStateEnum.noMessage:
      case AssistanceStateEnum.fetched:
      case AssistanceStateEnum.complete:
      case AssistanceStateEnum.error:
        return Theme.of(context).colorScheme.surfaceContainerHighest;
      case AssistanceStateEnum.notFetched:
      case AssistanceStateEnum.fetching:
        return Theme.of(context).colorScheme.primaryContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller.choreographer.textController,
      builder: (context, _, __) {
        final icon = Icon(
          size: 36,
          Icons.autorenew_rounded,
          color: assistanceState.stateColor(context),
        );
        return Tooltip(
          message: _enableFeedback ? L10n.of(context).check : "",
          child: Material(
            elevation: _enableFeedback ? 4.0 : 0.0,
            borderRadius: BorderRadius.circular(99.0),
            shadowColor: Theme.of(context).colorScheme.surface.withAlpha(128),
            child: InkWell(
              enableFeedback: _enableFeedback,
              onTap: _enableFeedback ? _onTap : null,
              customBorder: const CircleBorder(),
              onLongPress: _enableFeedback
                  ? () => showDialog(
                        context: context,
                        builder: (c) => const SettingsLearning(),
                        barrierDismissible: false,
                      )
                  : null,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    height: 40.0,
                    width: 40.0,
                    duration: FluffyThemes.animationDuration,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _backgroundColor,
                    ),
                  ),
                  _controller != null
                      ? RotationTransition(
                          turns: Tween(begin: 0.0, end: math.pi * 2)
                              .animate(_controller!),
                          child: icon,
                        )
                      : icon,
                  AnimatedContainer(
                    width: 20,
                    height: 20,
                    duration: FluffyThemes.animationDuration,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _backgroundColor,
                    ),
                  ),
                  Icon(
                    size: 16,
                    Icons.check,
                    color: assistanceState.stateColor(context),
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
