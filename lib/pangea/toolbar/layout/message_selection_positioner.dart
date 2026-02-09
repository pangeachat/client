import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/reaction_listener.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/instructions/instructions_inline_tooltip.dart';
import 'package:fluffychat/pangea/languages/language_constants.dart';
import 'package:fluffychat/pangea/languages/locale_provider.dart';
import 'package:fluffychat/pangea/toolbar/layout/over_message_overlay.dart';
import 'package:fluffychat/pangea/toolbar/layout/practice_mode_transition_animation.dart';
import 'package:fluffychat/pangea/toolbar/layout/reading_assistance_mode_enum.dart';
import 'package:fluffychat/pangea/toolbar/message_practice/reading_assistance_input_bar.dart';
import 'package:fluffychat/pangea/toolbar/message_selection_overlay.dart';
import 'package:fluffychat/pangea/toolbar/word_card/word_card_switcher.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Controls positioning of the message overlay.
class MessageSelectionPositioner extends StatefulWidget {
  final MessageOverlayController overlayController;
  final ChatController chatController;
  final Event event;
  final PangeaToken? initialSelectedToken;
  final Event? nextEvent;
  final Event? prevEvent;

  const MessageSelectionPositioner({
    required this.overlayController,
    required this.chatController,
    required this.event,
    this.initialSelectedToken,
    this.nextEvent,
    this.prevEvent,
    super.key,
  });

  @override
  MessageSelectionPositionerState createState() =>
      MessageSelectionPositionerState();
}

class MessageSelectionPositionerState extends State<MessageSelectionPositioner>
    with TickerProviderStateMixin {
  ScrollController? scrollController;

  ValueNotifier<bool> finishedTransition = ValueNotifier(false);
  final ValueNotifier<bool> _startedTransition = ValueNotifier(false);

  ReadingAssistanceMode readingAssistanceMode =
      ReadingAssistanceMode.selectMode;

  PangeaMessageEvent get pangeaMessageEvent =>
      widget.overlayController.pangeaMessageEvent;

  ReactionListener? _reactionListener;
  final ValueNotifier<double?> reactionNotifier = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController(
      onAttach: (position) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            scrollController?.jumpTo(
              scrollController!.position.maxScrollExtent,
            );
          }
        });
      },
    );

    reactionNotifier.value = _reactionsWidth;
    _reactionListener = ReactionListener(
      event: widget.event,
      onUpdate: (update) {
        if (mounted) {
          final newWidth = _reactionsWidth;
          if (newWidth != reactionNotifier.value) {
            reactionNotifier.value = newWidth;
          }
        }
      },
    );
  }

  @override
  void dispose() {
    reactionNotifier.dispose();
    _reactionListener?.dispose();
    scrollController?.dispose();
    super.dispose();
  }

  T _runWithLogging<T>(
    Function runner,
    String errorMessage,
    T defaultValue,
  ) {
    try {
      return runner();
    } catch (e, s) {
      ErrorHandler.logError(
        e: "$errorMessage: $e",
        s: s,
        data: {
          "eventID": widget.event.eventId,
        },
      );
      return defaultValue;
    }
  }

  final Duration transitionAnimationDuration =
      const Duration(milliseconds: 300);

  double get _horizontalPadding =>
      FluffyThemes.isColumnMode(context) ? 8.0 : 0.0;

  bool get hasReactions {
    final reactionsEvents = widget.event.aggregatedEvents(
      widget.chatController.timeline!,
      RelationshipTypes.reaction,
    );
    return reactionsEvents.where((e) => !e.redacted).isNotEmpty;
  }

  double get _reactionsHeight {
    if (_reactionsRenderBox != null) {
      return _reactionsRenderBox!.size.height;
    }
    return hasReactions ? 28.0 : 0.0;
  }

  double? get _reactionsWidth {
    if (_reactionsRenderBox != null) {
      return _reactionsRenderBox!.size.width;
    }
    return null;
  }

  bool get ownMessage =>
      widget.event.senderId == widget.event.room.client.userID;

  bool get showDetails =>
      AppSettings.displayChatDetailsColumn.getItem(Matrix.of(context).store) &&
      FluffyThemes.isThreeColumnMode(context) &&
      widget.chatController.room.membership == Membership.join;

  MediaQueryData? get mediaQuery => _runWithLogging<MediaQueryData?>(
        () => MediaQuery.of(context),
        "Error getting media query",
        null,
      );

  double get columnWidth => FluffyThemes.isColumnMode(context)
      ? (FluffyThemes.columnWidth + FluffyThemes.navRailWidth + 2.0)
      : 0;

  double get _toolbarMaxWidth {
    const double messageMargin = 16.0;
    // widget.event.isActivityMessage ? 0 : Avatar.defaultSize + 16 + 8;
    final bool showingDetails = widget.chatController.displayChatDetailsColumn;
    final double totalMaxWidth = FluffyThemes.maxTimelineWidth -
        (showingDetails ? FluffyThemes.columnWidth : 0) -
        messageMargin;
    double? maxWidth;

    if (mediaQuery != null) {
      final chatViewWidth = mediaQuery!.size.width - columnWidth;
      maxWidth = chatViewWidth - (2 * _horizontalPadding) - messageMargin;
    }

    if (maxWidth == null || maxWidth > totalMaxWidth) {
      maxWidth = totalMaxWidth;
    }

    return maxWidth;
  }

  Size get _defaultMessageSize => const Size(FluffyThemes.columnWidth / 2, 100);

  RenderBox? get _overlayMessageRenderBox => _runWithLogging<RenderBox?>(
        () => MatrixState.pAnyState.getRenderBox(
          'overlay_message_${widget.event.eventId}',
        ),
        "Error getting overlay message render box",
        null,
      );

  RenderBox? get _reactionsRenderBox => _runWithLogging<RenderBox?>(
        () => MatrixState.pAnyState.getRenderBox(
          'message_reactions_${widget.event.eventId}',
        ),
        "Error getting reactions render box",
        null,
      );

  Size? get _overlayMessageSize => _overlayMessageRenderBox?.size;

  Offset? get overlayMessageOffset {
    if (_overlayMessageRenderBox == null ||
        !_overlayMessageRenderBox!.hasSize) {
      return null;
    }
    return _runWithLogging(
      () => _overlayMessageRenderBox?.localToGlobal(Offset.zero),
      "Error getting overlay message offset",
      null,
    );
  }

  RenderBox? get _messageRenderBox => _runWithLogging<RenderBox?>(
        () => MatrixState.pAnyState.getRenderBox(
          widget.event.eventId,
        ),
        "Error getting message render box",
        null,
      );

  Offset? get _originalMessageOffset {
    if (_messageRenderBox == null || !_messageRenderBox!.hasSize) {
      return null;
    }
    return _runWithLogging(
      () => _messageRenderBox?.localToGlobal(Offset.zero),
      "Error getting message offset",
      null,
    );
  }

  /// The size of the message in the chat list (as opposed to the expanded size in the center overlay)
  Size get originalMessageSize {
    if (_messageRenderBox == null || !_messageRenderBox!.hasSize) {
      return _defaultMessageSize;
    }

    return _runWithLogging(
      () => _messageRenderBox?.size,
      "Error getting message size",
      _defaultMessageSize,
    );
  }

  bool get isRtl {
    final locale = Provider.of<LocaleProvider>(context, listen: false)
        .locale
        ?.languageCode;
    return locale != null &&
        LanguageConstants.rtlLanguageCodes.contains(locale);
  }

  double? get messageLeftOffset {
    if (ownMessage) return null;

    final offset = _originalMessageOffset;
    if (offset == null) {
      return Avatar.defaultSize + 16;
    }

    if (isRtl) {
      return offset.dx - (showDetails ? FluffyThemes.columnWidth : 0);
    }

    if (ownMessage) return null;
    return max(offset.dx - columnWidth, 0);
  }

  double? get messageRightOffset {
    if (mediaQuery == null || !ownMessage) return null;

    final offset = _originalMessageOffset;
    if (offset == null) {
      return 8.0;
    }

    if (isRtl) {
      return mediaQuery!.size.width -
          columnWidth -
          offset.dx -
          originalMessageSize.width;
    }

    return mediaQuery!.size.width -
        offset.dx -
        originalMessageSize.width -
        (showDetails ? FluffyThemes.columnWidth : 0);
  }

  Alignment get messageAlignment {
    return ownMessage ? Alignment.bottomRight : Alignment.bottomLeft;
  }

  CrossAxisAlignment get messageColumnAlignment {
    if (isRtl) {
      return ownMessage ? CrossAxisAlignment.start : CrossAxisAlignment.end;
    }
    return ownMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start;
  }

  double get _contentHeight {
    final messageHeight =
        _overlayMessageSize?.height ?? originalMessageSize.height;
    return messageHeight + _reactionsHeight + AppConfig.toolbarMenuHeight + 4.0;
  }

  double get overheadContentHeight {
    return (widget.overlayController.selectedToken != null
            ? AppConfig.toolbarMaxHeight
            : 40.0) +
        4.0;
  }

  double? get _wordCardLeftOffset {
    if (ownMessage) return null;
    if (widget.overlayController.selectedToken != null &&
        mediaQuery != null &&
        (mediaQuery!.size.width < _toolbarMaxWidth + messageLeftOffset!)) {
      return mediaQuery!.size.width - _toolbarMaxWidth - 8.0;
    }
    return messageLeftOffset;
  }

  double get _fullContentHeight {
    return _contentHeight + overheadContentHeight;
  }

  double? get _screenHeight {
    if (mediaQuery == null) return null;
    return mediaQuery!.size.height -
        mediaQuery!.padding.bottom -
        mediaQuery!.padding.top;
  }

  bool get shouldScroll {
    if (_screenHeight == null) return false;
    return _fullContentHeight > _screenHeight!;
  }

  bool get _hasFooterOverflow {
    if (_screenHeight == null) return false;
    final offset = _originalMessageOffset;
    if (offset == null) return false;

    final bottomOffset = offset.dy +
        originalMessageSize.height +
        _reactionsHeight +
        AppConfig.toolbarMenuHeight +
        4.0;

    return bottomOffset >
        (_screenHeight! + MediaQuery.paddingOf(context).bottom);
  }

  double get spaceBelowContent {
    if (shouldScroll) return 0;
    if (_hasFooterOverflow) return 0;
    final offset = _originalMessageOffset;
    if (offset == null) return 300;

    final messageHeight = originalMessageSize.height;
    final originalContentHeight =
        messageHeight + _reactionsHeight + AppConfig.toolbarMenuHeight + 8.0;

    final screenHeight = mediaQuery!.size.height - mediaQuery!.padding.bottom;

    double boxHeight = screenHeight - offset.dy - originalContentHeight;

    final neededSpace =
        boxHeight + _fullContentHeight + mediaQuery!.padding.top + 4.0;

    if (neededSpace > screenHeight) {
      boxHeight =
          screenHeight - _fullContentHeight - mediaQuery!.padding.top - 4.0;
    }

    return boxHeight;
  }

  void onStartedTransition() {
    if (mounted) _startedTransition.value = true;
  }

  void onFinishedTransition() {
    if (mounted) finishedTransition.value = true;
  }

  void launchPractice(ReadingAssistanceMode mode) {
    if (MatrixState.pangeaController.subscriptionController.isSubscribed ==
        false) {
      return;
    }

    if (mounted) {
      setState(() => readingAssistanceMode = mode);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_messageRenderBox == null || mediaQuery == null) {
      return const SizedBox.shrink();
    }

    widget.overlayController.maxWidth = _toolbarMaxWidth;
    return SafeArea(
      child: Row(
        children: [
          Column(
            children: [
              SizedBox(
                width: mediaQuery!.size.width -
                    columnWidth -
                    (showDetails ? FluffyThemes.columnWidth : 0),
                height: _screenHeight!,
                child: Stack(
                  alignment:
                      ownMessage ? Alignment.centerRight : Alignment.centerLeft,
                  children: [
                    ValueListenableBuilder(
                      valueListenable: _startedTransition,
                      builder: (context, started, __) {
                        return !started
                            ? OverMessageOverlay(controller: this)
                            : const SizedBox();
                      },
                    ),
                    ValueListenableBuilder(
                      valueListenable: _startedTransition,
                      builder: (context, started, __) {
                        return !started && shouldScroll
                            ? Positioned(
                                top: 0,
                                left: _wordCardLeftOffset,
                                right: messageRightOffset,
                                child: WordCardSwitcher(controller: this),
                              )
                            : const SizedBox();
                      },
                    ),
                    if (readingAssistanceMode ==
                        ReadingAssistanceMode.practiceMode) ...[
                      CenteredMessage(
                        controller: this,
                      ),
                      PracticeModeTransitionAnimation(
                        targetId:
                            "overlay_center_message_${widget.event.eventId}",
                        controller: this,
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 20,
                        child: ReadingAssistanceInputBar(
                          widget.overlayController.practiceController,
                          maxWidth: widget.overlayController.maxWidth,
                          selectedToken: widget.overlayController.selectedToken,
                        ),
                      ),
                      Positioned(
                        top: FluffyThemes.isColumnMode(context)
                            ? switch (MediaQuery.heightOf(context)) {
                                < 700 => 0,
                                > 900 => 160,
                                _ => 80,
                              }
                            : 0,
                        left: 0,
                        right: 0,
                        child: ListenableBuilder(
                          listenable:
                              widget.overlayController.practiceController,
                          builder: (context, _) {
                            final practice =
                                widget.overlayController.practiceController;

                            final instruction =
                                practice.practiceMode.instruction;

                            final type =
                                practice.practiceMode.associatedActivityType;
                            final complete = type != null &&
                                practice.isPracticeSessionDone(type);

                            if (instruction != null && !complete) {
                              return InstructionsInlineTooltip(
                                instructionsEnum: widget
                                    .overlayController
                                    .practiceController
                                    .practiceMode
                                    .instruction!,
                                padding: const EdgeInsets.all(16.0),
                                animate: false,
                              );
                            }

                            return const SizedBox();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (showDetails)
            const SizedBox(
              width: FluffyThemes.columnWidth,
            ),
        ],
      ),
    );
  }
}

class MessageReactionPicker extends StatelessWidget {
  final ChatController chatController;
  const MessageReactionPicker({
    super.key,
    required this.chatController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sentReactions = <String>{};
    final event = chatController.selectedEvents.firstOrNull;
    if (event != null) {
      sentReactions.addAll(
        event
            .aggregatedEvents(
              chatController.timeline!,
              RelationshipTypes.reaction,
            )
            .where(
              (event) =>
                  event.senderId == event.room.client.userID &&
                  event.type == 'm.reaction',
            )
            .map(
              (event) => event.content
                  .tryGetMap<String, Object?>('m.relates_to')
                  ?.tryGet<String>('key'),
            )
            .whereType<String>(),
      );
    }

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(
        AppConfig.borderRadius,
      ),
      shadowColor: theme.colorScheme.surface.withAlpha(128),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          height: 40.0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...AppConfig.defaultReactions.map(
                (emoji) => IconButton(
                  padding: EdgeInsets.zero,
                  icon: Center(
                    child: Opacity(
                      opacity: sentReactions.contains(
                        emoji,
                      )
                          ? 0.33
                          : 1,
                      child: Text(
                        emoji,
                        style: const TextStyle(
                          fontSize: 20,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  onPressed: sentReactions.contains(emoji)
                      ? null
                      : () => event?.room.sendReaction(
                            event.eventId,
                            emoji,
                          ),
                ),
              ),
              // IconButton(
              //   icon: const Icon(
              //     Icons.add_reaction_outlined,
              //   ),
              //   tooltip: L10n.of(context).customReaction,
              //   onPressed: () async {
              //     final emoji = await showAdaptiveBottomSheet<String>(
              //       context: context,
              //       builder: (context) => Scaffold(
              //         appBar: AppBar(
              //           title: Text(
              //             L10n.of(context).customReaction,
              //           ),
              //           leading: CloseButton(
              //             onPressed: () => Navigator.of(
              //               context,
              //             ).pop(
              //               null,
              //             ),
              //           ),
              //         ),
              //         body: SizedBox(
              //           height: double.infinity,
              //           child: EmojiPicker(
              //             onEmojiSelected: (
              //               _,
              //               emoji,
              //             ) =>
              //                 Navigator.of(
              //               context,
              //             ).pop(
              //               emoji.emoji,
              //             ),
              //             config: Config(
              //               emojiViewConfig: const EmojiViewConfig(
              //                 backgroundColor: Colors.transparent,
              //               ),
              //               bottomActionBarConfig: const BottomActionBarConfig(
              //                 enabled: false,
              //               ),
              //               categoryViewConfig: CategoryViewConfig(
              //                 initCategory: Category.SMILEYS,
              //                 backspaceColor: theme.colorScheme.primary,
              //                 iconColor: theme.colorScheme.primary.withAlpha(
              //                   128,
              //                 ),
              //                 iconColorSelected: theme.colorScheme.primary,
              //                 indicatorColor: theme.colorScheme.primary,
              //                 backgroundColor: theme.colorScheme.surface,
              //               ),
              //               skinToneConfig: SkinToneConfig(
              //                 dialogBackgroundColor: Color.lerp(
              //                   theme.colorScheme.surface,
              //                   theme.colorScheme.primaryContainer,
              //                   0.75,
              //                 )!,
              //                 indicatorColor: theme.colorScheme.onSurface,
              //               ),
              //             ),
              //           ),
              //         ),
              //       ),
              //     );
              //     if (emoji == null) return;
              //     if (sentReactions.contains(emoji)) return;
              //     await event?.room.sendReaction(
              //       event.eventId,
              //       emoji,
              //     );
              //   },
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
