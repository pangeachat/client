import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/routes/analytics/analytics_navigation_util.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/restore_constructs_mixin.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/phonetic_transcription_widget.dart';
import 'package:fluffychat/routes/chat/events/phonetic_transcription/pt_v2_models.dart';
import 'package:fluffychat/routes/chat/events/tokens/tokens_util.dart';
import 'package:fluffychat/routes/chat/toolbar/reading_assistance/new_word_overlay.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/lemma_meaning_display.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/lemma_reaction_picker.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/message_unsubscribed_card.dart';
import 'package:fluffychat/routes/chat/toolbar/word_card/token_feedback_button.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class WordZoomWidget extends StatelessWidget {
  final PangeaTokenText token;
  final ConstructIdentifier construct;
  final String langCode;

  final VoidCallback? onClose;
  final Event? event;

  /// POS tag for PT v2 disambiguation (e.g. "VERB").
  final String pos;

  /// Morph features for PT v2 disambiguation (e.g. {"Tense": "Past"}).
  final Map<String, String>? morph;

  final bool enableEmojiSelection;
  final bool enableEmojiReactions;
  final bool enableAnalyticsNavigation;

  /// Whether a blocked construct may be restored from this card's header slot.
  /// False only where the host already offers a restore of its own — the vocab
  /// details page — so the user never sees two restore affordances at once.
  final bool enableRestore;

  final Function(LemmaInfoResponse, PTRequest, PTResponse)? onFlagTokenInfo;
  final ValueNotifier<int>? reloadNotifier;
  final double? maxWidth;

  const WordZoomWidget({
    super.key,
    required this.token,
    required this.construct,
    required this.langCode,
    required this.pos,
    required this.enableEmojiSelection,
    required this.enableEmojiReactions,
    this.onClose,
    this.event,
    this.morph,
    this.enableAnalyticsNavigation = false,
    this.enableRestore = true,
    this.onFlagTokenInfo,
    this.reloadNotifier,
    this.maxWidth,
  });

  void _showNewWordOverlay(BuildContext context) {
    if (TokensUtil.instance.isRecentlyCollected(token)) {
      NewWordOverlay.show(
        context: context,
        target: token.wordCardTargetKey,
        overlayKey: "new-word-${token.uniqueKey}",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      _showNewWordOverlay(context);
    });

    final Widget content =
        !MatrixState
            .pangeaController
            .subscriptionController
            .showSubscriptionGatedContent
        ? MessageUnsubscribedCard(token: token, onClose: onClose)
        : Container(
            height: AppConfig.toolbarMaxHeight - 8,
            padding: const EdgeInsets.all(12.0),
            constraints: BoxConstraints(
              maxWidth: maxWidth ?? AppConfig.toolbarMinWidth,
            ),
            child: Column(
              spacing: 12.0,
              children: [
                _WordCardHeader(
                  token: token,
                  construct: construct,
                  langCode: langCode,
                  event: event,
                  onClose: onClose,
                  onFlagTokenInfo: onFlagTokenInfo,
                  enableAnalyticsNavigation: enableAnalyticsNavigation,
                  enableRestore: enableRestore,
                ),
                Expanded(
                  child: Column(
                    spacing: 4.0,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      PhoneticTranscriptionWidget(
                        text: token.content,
                        textLanguage:
                            PLanguageStore.byLangCode(langCode) ??
                            LanguageModel.unknown,
                        pos: pos,
                        morph: morph,
                        style: const TextStyle(fontSize: 14.0),
                        maxLines: 2,
                        reloadNotifier: reloadNotifier,
                      ),
                      LemmaReactionPicker(
                        constructId: construct,
                        langCode: langCode,
                        event: event,
                        enableSelection: enableEmojiSelection,
                        enableReactions: enableEmojiReactions,
                        form: token.content,
                      ),
                      LemmaMeaningDisplay(
                        langCode: langCode,
                        constructId: construct,
                        text: token.content,
                        messageInfo: event?.content ?? {},
                        reloadNotifier: reloadNotifier,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

    return GestureDetector(
      onTap: () {
        // Absorb taps to prevent them from propagating
        // to widgets below and closing the overlay.
      },
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(
              width: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
            borderRadius: const BorderRadius.all(Radius.circular(25)),
          ),
          height: AppConfig.toolbarMaxHeight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [content],
          ),
        ),
      ),
    );
  }
}

/// The card's header row: close, the word itself, and a trailing slot.
///
/// Stateful because two of its parts track whether the construct is currently
/// blocked — the trailing slot swaps the feedback flag for a restore button, and
/// the title dims — while [WordZoomWidget] is stateless with no analytics
/// subscription of its own. Without the subscription the card would keep showing
/// Restore after the user tapped it, since blocked state lives in Matrix room
/// state rather than in this widget.
class _WordCardHeader extends StatefulWidget {
  final PangeaTokenText token;
  final ConstructIdentifier construct;
  final String langCode;
  final Event? event;
  final VoidCallback? onClose;
  final Function(LemmaInfoResponse, PTRequest, PTResponse)? onFlagTokenInfo;
  final bool enableAnalyticsNavigation;
  final bool enableRestore;

  const _WordCardHeader({
    required this.token,
    required this.construct,
    required this.langCode,
    required this.event,
    required this.onClose,
    required this.onFlagTokenInfo,
    required this.enableAnalyticsNavigation,
    required this.enableRestore,
  });

  @override
  State<_WordCardHeader> createState() => _WordCardHeaderState();
}

class _WordCardHeaderState extends State<_WordCardHeader>
    with ConstructRestorer {
  StreamSubscription<AnalyticsStreamUpdate>? _updateSub;
  late bool _blocked;

  @override
  void initState() {
    super.initState();
    _blocked = _readBlocked();
    _updateSub = Matrix.of(context)
        .analyticsDataService
        .updateDispatcher
        .constructUpdateStream
        .stream
        .listen((_) => _refresh());
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    super.dispose();
  }

  bool _readBlocked() => Matrix.of(
    context,
  ).analyticsDataService.isConstructBlocked(widget.construct);

  /// Re-derived from room state rather than read off the update, so a block or
  /// restore of THIS construct from any surface or device lands the same way.
  void _refresh() {
    if (!mounted) return;
    final blocked = _readBlocked();
    if (blocked != _blocked) setState(() => _blocked = blocked);
  }

  @override
  Widget build(BuildContext context) {
    final showRestore = _blocked && widget.enableRestore;

    return SizedBox(
      height: 40.0,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.onClose != null
              ? IconButton(
                  tooltip: L10n.of(context).close,
                  color: Theme.of(context).iconTheme.color,
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                )
              : const SizedBox(width: 40.0, height: 40.0),
          Flexible(
            child: Opacity(
              opacity: _blocked ? 0.5 : 1.0,
              child: InkWell(
                onTap: widget.enableAnalyticsNavigation
                    ? () => AnalyticsNavigationUtil.navigateToAnalytics(
                        context: context,
                        view: ProgressIndicatorEnum.wordsUsed,
                        construct: widget.construct,
                      )
                    : null,
                borderRadius: BorderRadius.circular(8.0),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40.0),
                  alignment: Alignment.center,
                  child: Text(
                    widget.token.content,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28.0,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: Theme.of(context).brightness == Brightness.light
                          ? AppConfig.yellowDark
                          : AppConfig.yellowLight,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The restore button takes the flag's slot rather than adding a
          // fourth control, keeping the header balanced against the close
          // button. Token feedback on a deleted word is the lesser need.
          if (showRestore)
            IconButton(
              tooltip: L10n.of(context).restore,
              color: Theme.of(context).colorScheme.error,
              icon: const Icon(Icons.restore_from_trash_outlined),
              onPressed: () => restoreConstructs(context, [widget.construct]),
            )
          else if (widget.onFlagTokenInfo != null)
            TokenFeedbackButton(
              textLanguage:
                  PLanguageStore.byLangCode(widget.langCode) ??
                  LanguageModel.unknown,
              constructId: widget.construct,
              text: widget.token.content,
              onFlagTokenInfo: widget.onFlagTokenInfo!,
              messageInfo: widget.event?.content ?? {},
            )
          else
            const SizedBox(width: 40.0, height: 40.0),
        ],
      ),
    );
  }
}
