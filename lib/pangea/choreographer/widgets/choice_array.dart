import 'dart:developer';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fluffychat/pangea/widgets/chat/tts_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

import '../../utils/bot_style.dart';
import 'it_shimmer.dart';

typedef ChoiceCallback = void Function(String value, int index);

class ChoicesArray extends StatefulWidget {
  final bool isLoading;
  final List<Choice>? choices;
  final ChoiceCallback onPressed;
  final ChoiceCallback? onLongPress;
  final int? selectedChoiceIndex;
  final String originalSpan;
  final String Function(int) uniqueKeyForLayerLink;

  /// If null then should not be used
  /// We don't want tts in the case of L1 options
  final TtsController? tts;

  final bool enableAudio;

  /// Used to unqiuely identify the keys for choices, in cases where multiple
  /// choices could have identical text, like in back-to-back practice activities
  final String? id;

  /// some uses of this widget want to disable clicking of the choices
  final bool isActive;

  const ChoicesArray({
    super.key,
    required this.isLoading,
    required this.choices,
    required this.onPressed,
    required this.originalSpan,
    required this.uniqueKeyForLayerLink,
    required this.selectedChoiceIndex,
    required this.tts,
    this.enableAudio = true,
    this.isActive = true,
    this.onLongPress,
    this.id,
  });

  @override
  ChoicesArrayState createState() => ChoicesArrayState();
}

class ChoicesArrayState extends State<ChoicesArray> {
  bool interactionDisabled = false;

  void disableInteraction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => interactionDisabled = true);
    });
  }

  void enableInteractions() {
    if (_hasSelectedCorrectChoice) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => interactionDisabled = false);
    });
  }

  bool get _hasSelectedCorrectChoice =>
      widget.choices?.any((choice) => choice.isGold && choice.color != null) ??
      false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return widget.isLoading &&
            (widget.choices == null || widget.choices!.length <= 1)
        ? ItShimmer(originalSpan: widget.originalSpan)
        : Wrap(
            alignment: WrapAlignment.center,
            children: widget.choices!
                .mapIndexed(
                  (index, entry) => ChoiceItem(
                    theme: theme,
                    onLongPress: widget.isActive ? widget.onLongPress : null,
                    onPressed: widget.isActive
                        ? (String value, int index) {
                            widget.onPressed(value, index);
                            // TODO - what to pass here as eventID?
                            if (widget.enableAudio && widget.tts != null) {
                              widget.tts?.tryToSpeak(value, context, null);
                            }
                          }
                        : (String value, int index) {
                            debugger(when: kDebugMode);
                          },
                    entry: MapEntry(index, entry),
                    interactionDisabled: interactionDisabled,
                    enableInteraction: enableInteractions,
                    disableInteraction: disableInteraction,
                    isSelected: widget.selectedChoiceIndex == index,
                    id: widget.id,
                  ),
                )
                .toList(),
          );
  }
}

class Choice {
  Choice({
    this.color,
    required this.text,
    this.isGold = false,
  });

  final Color? color;
  final String text;
  final bool isGold;
}

class ChoiceItem extends StatelessWidget {
  const ChoiceItem({
    super.key,
    required this.theme,
    required this.onLongPress,
    required this.onPressed,
    required this.entry,
    required this.isSelected,
    required this.interactionDisabled,
    required this.enableInteraction,
    required this.disableInteraction,
    required this.id,
  });

  final MapEntry<int, Choice> entry;
  final ThemeData theme;
  final ChoiceCallback? onLongPress;
  final ChoiceCallback onPressed;
  final bool isSelected;
  final bool interactionDisabled;
  final VoidCallback enableInteraction;
  final VoidCallback disableInteraction;
  final String? id;

  @override
  Widget build(BuildContext context) {
    try {
      return Tooltip(
        message: onLongPress != null ? L10n.of(context)!.holdForInfo : "",
        waitDuration: onLongPress != null
            ? const Duration(milliseconds: 500)
            : const Duration(days: 1),
        child: ChoiceAnimationWidget(
          key: ValueKey("${entry.value.text}$id"),
          selected: entry.value.color != null,
          isGold: entry.value.isGold,
          enableInteraction: enableInteraction,
          disableInteraction: disableInteraction,
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: EdgeInsets.zero,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              border: Border.all(
                color: isSelected
                    ? entry.value.color ?? theme.colorScheme.primary
                    : Colors.transparent,
                style: BorderStyle.solid,
                width: 2.0,
              ),
            ),
            child: TextButton(
              style: ButtonStyle(
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 7),
                ),
                //if index is selected, then give the background a slight primary color
                backgroundColor: entry.value.color != null
                    ? WidgetStateProperty.all<Color>(
                        entry.value.color!.withOpacity(0.2),
                      )
                    // : theme.colorScheme.primaryFixed,
                    : null,
                textStyle: WidgetStateProperty.all(
                  BotStyle.text(context),
                ),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              onLongPress: onLongPress != null && !interactionDisabled
                  ? () => onLongPress!(entry.value.text, entry.key)
                  : null,
              onPressed: interactionDisabled
                  ? null
                  : () => onPressed(entry.value.text, entry.key),
              child: Text(
                entry.value.text,
                style: BotStyle.text(context),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      debugger(when: kDebugMode);
      return Container();
    }
  }
}

class ChoiceAnimationWidget extends StatefulWidget {
  final Widget child;
  final bool selected;
  final bool isGold;
  final VoidCallback enableInteraction;
  final VoidCallback disableInteraction;

  const ChoiceAnimationWidget({
    super.key,
    required this.child,
    required this.selected,
    required this.enableInteraction,
    required this.disableInteraction,
    this.isGold = false,
  });

  @override
  ChoiceAnimationWidgetState createState() => ChoiceAnimationWidgetState();
}

enum AnimationState { ready, forward, reverse, finished }

class ChoiceAnimationWidgetState extends State<ChoiceAnimationWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  AnimationState animationState = AnimationState.ready;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _animation = widget.isGold
        ? Tween<double>(begin: 1.0, end: 1.2).animate(_controller)
        : TweenSequence<double>([
            TweenSequenceItem<double>(
              tween: Tween<double>(begin: 0, end: -8 * pi / 180),
              weight: 1.0,
            ),
            TweenSequenceItem<double>(
              tween: Tween<double>(begin: -8 * pi / 180, end: 16 * pi / 180),
              weight: 2.0,
            ),
            TweenSequenceItem<double>(
              tween: Tween<double>(begin: 16 * pi / 180, end: 0),
              weight: 1.0,
            ),
          ]).animate(_controller);

    widget.enableInteraction();

    if (widget.selected && animationState == AnimationState.ready) {
      widget.disableInteraction();
      _controller.forward();
      setState(() {
        animationState = AnimationState.forward;
      });
    }
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          animationState == AnimationState.forward) {
        _controller.reverse();
        setState(() {
          animationState = AnimationState.reverse;
        });
      }
      if (status == AnimationStatus.dismissed &&
          animationState == AnimationState.reverse) {
        widget.enableInteraction();
        setState(() {
          animationState = AnimationState.finished;
        });
      }
    });
  }

  @override
  void didUpdateWidget(ChoiceAnimationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && animationState == AnimationState.ready) {
      widget.disableInteraction();
      _controller.forward();
      setState(() {
        animationState = AnimationState.forward;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.isGold
        ? AnimatedBuilder(
            key: UniqueKey(),
            animation: _animation,
            builder: (context, child) {
              return Transform.scale(
                scale: _animation.value,
                child: child,
              );
            },
            child: widget.child,
          )
        : AnimatedBuilder(
            key: UniqueKey(),
            animation: _animation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _animation.value,
                child: child,
              );
            },
            child: widget.child,
          );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
