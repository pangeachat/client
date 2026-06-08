import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/chat/events/reaction_listener.dart';
import 'package:fluffychat/pangea/analytics_misc/analytics_navigation_util.dart';
import 'package:fluffychat/pangea/analytics_misc/lemma_emoji_setter_mixin.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/shimmer_background.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/lemmas/lemma_meaning_builder.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LemmaReactionPicker extends StatefulWidget {
  final Event? event;
  final ConstructIdentifier constructId;
  final String langCode;
  final String? form;

  final bool enableSelection;
  final bool enableReactions;

  const LemmaReactionPicker({
    super.key,
    required this.constructId,
    required this.langCode,
    this.event,
    this.enableSelection = true,
    this.enableReactions = true,
    this.form,
  });

  @override
  LemmaReactionPickerState createState() => LemmaReactionPickerState();
}

class LemmaReactionPickerState extends State<LemmaReactionPicker>
    with LemmaEmojiSetter {
  String? _selectedEmoji;
  Map<String, Event> _userReactionEvents = {};

  ScaffoldMessengerState? messenger;
  StreamSubscription? _lemmaEmojiUpdateSubscription;
  ReactionListener? _reactionSubscription;

  @override
  void initState() {
    super.initState();
    _selectedEmoji = widget.constructId.userSetEmoji;
    _setEmojiSub();
    _setReactionSub();
    _setUserReactionEvents();
  }

  @override
  void didUpdateWidget(LemmaReactionPicker oldWidget) {
    if (oldWidget.constructId != widget.constructId) {
      _setSelectedEmoji(widget.constructId.userSetEmoji);
      _setEmojiSub();
    }

    if (oldWidget.event?.eventId != widget.event?.eventId) {
      _setReactionSub();
      _setUserReactionEvents();
    }

    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    messenger?.hideCurrentSnackBar();
    messenger = null;
    _lemmaEmojiUpdateSubscription?.cancel();
    _reactionSubscription?.dispose();
    super.dispose();
  }

  bool get _matchesL2 =>
      widget.langCode.split("-").first ==
      MatrixState.pangeaController.userController.userL2?.langCodeShort;

  void _setEmojiSub() {
    _lemmaEmojiUpdateSubscription?.cancel();
    _lemmaEmojiUpdateSubscription = Matrix.of(context)
        .analyticsDataService
        .updateDispatcher
        .lemmaUpdateStream(widget.constructId)
        .listen((update) => _setSelectedEmoji(update.emojis?.firstOrNull));
  }

  void _setReactionSub() {
    _reactionSubscription?.dispose();

    final event = widget.event;
    if (event == null) {
      _reactionSubscription = null;
      return;
    }

    _reactionSubscription = ReactionListener(
      event: event,
      onUpdate: (_) => _setUserReactionEvents(),
    );
  }

  void _setSelectedEmoji(String? emoji) {
    if (_selectedEmoji != emoji) {
      setState(() => _selectedEmoji = emoji);
    }
  }

  void _setUserReactionEvents() {
    final event = widget.event;
    if (event == null) return;

    final updatedEvents = event
        .aggregatedEvents(event.room.timeline!, RelationshipTypes.reaction)
        .where((e) => e.senderId == Matrix.of(context).client.userID)
        .toList();

    final Map<String, Event> updateEventsMap = {};
    for (final event in updatedEvents) {
      final emoji = event.content.tryGetMap('m.relates_to')?['key'];
      if (emoji is! String) continue;
      updateEventsMap[emoji] = event;
    }

    setState(() => _userReactionEvents = updateEventsMap);
  }

  Future<void> _setLemmaEmoji(String emoji, String targetId) async {
    await setLemmaEmoji(
      widget.constructId,
      widget.langCode,
      emoji,
      targetId,
      widget.event?.roomId,
      widget.event?.eventId,
      widget.form,
    );

    _showLemmaEmojiSnackbar();
  }

  void _showLemmaEmojiSnackbar() {
    messenger ??= ScaffoldMessenger.of(context);
    showLemmaEmojiSnackbar(messenger!, context, widget.constructId, () {
      if (!mounted) return;
      AnalyticsNavigationUtil.navigateToAnalytics(
        context: context,
        view: widget.constructId.type.indicator,
        construct: widget.constructId,
      );
    });
  }

  Future<void> _sendOrRedactReaction(String emoji) async {
    final event = widget.event;
    if (event == null || event.room.timeline == null) return;

    try {
      final reactionEvent = _userReactionEvents[emoji];
      reactionEvent != null
          ? await reactionEvent.redactEvent()
          : await event.room.sendReaction(event.eventId, emoji);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'emoji': emoji, 'eventId': event.eventId},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetIdBase =
        "emoji-choice-item-${widget.constructId.lemma}-$hashCode";

    final globallyEnable = _matchesL2;
    final globallyEnableSelection = globallyEnable && widget.enableSelection;
    final globallyEnableReactions = globallyEnable && widget.enableReactions;

    final bool hasSentSelectedEmojiReaction =
        _selectedEmoji != null &&
        _userReactionEvents.containsKey(_selectedEmoji!);

    final canShowReactionBadge =
        globallyEnableReactions && !hasSentSelectedEmojiReaction;

    return LemmaMeaningBuilder(
      langCode: widget.langCode,
      constructId: widget.constructId,
      messageInfo: widget.event?.content ?? {},
      builder: (context, controller) {
        return switch (controller.state) {
          AsyncError() => const SizedBox.shrink(),
          AsyncLoaded(value: final lemmaInfo) => SizedBox(
            height: 70.0,
            child: Row(
              spacing: 4.0,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...lemmaInfo.emoji.map((emoji) {
                  final selected = _selectedEmoji == emoji;
                  final targetId = "$targetIdBase-$emoji";

                  final showReactionBadge = canShowReactionBadge && selected;
                  final badge = showReactionBadge
                      ? const Icon(Icons.add_reaction, size: 12.0)
                      : null;

                  final enabled = selected
                      ? globallyEnableReactions
                      : globallyEnableSelection;

                  return HoverBuilder(
                    builder: (context, hovered) => MouseRegion(
                      cursor: enabled
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      child: GestureDetector(
                        onTap: enabled
                            ? () => emoji != _selectedEmoji
                                  ? _setLemmaEmoji(emoji, targetId)
                                  : _sendOrRedactReaction(emoji)
                            : null,
                        child: Stack(
                          children: [
                            ShimmerBackground(
                              enabled: enabled && _selectedEmoji == null,
                              delayBetweenPulses: const Duration(seconds: 5),
                              child: CompositedTransformTarget(
                                link: MatrixState.pAnyState
                                    .layerLinkAndKey(targetId)
                                    .link,
                                child: AnimatedContainer(
                                  key: MatrixState.pAnyState
                                      .layerLinkAndKey(targetId)
                                      .key,
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color:
                                        globallyEnableSelection &&
                                            (hovered || selected)
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.secondary.withAlpha(30)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(
                                      AppConfig.borderRadius,
                                    ),
                                    border: selected
                                        ? Border.all(
                                            color: Colors.transparent,
                                            width: 4,
                                          )
                                        : null,
                                  ),
                                  child: Text(
                                    emoji,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                ),
                              ),
                            ),
                            if (badge != null)
                              Positioned(right: 6, bottom: 6, child: badge),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          _ => SizedBox(
            height: 70.0,
            child: Row(
              spacing: 4.0,
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (_) => Shimmer.fromColors(
                  baseColor: Colors.transparent,
                  highlightColor: Theme.of(
                    context,
                  ).colorScheme.primary.withAlpha(70),
                  child: Container(
                    height: 55.0,
                    width: 55.0,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        };
      },
    );
  }
}
