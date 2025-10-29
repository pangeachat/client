import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choreographer_state_extension.dart';
import 'package:fluffychat/pangea/choreographer/enums/span_choice_type.dart';
import 'package:fluffychat/pangea/choreographer/enums/span_data_type.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_state.dart';
import 'package:fluffychat/pangea/choreographer/models/span_data.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/overlay.dart';
import 'package:fluffychat/pangea/toolbar/controllers/tts_controller.dart';
import '../../../../widgets/matrix.dart';
import '../../../bot/widgets/bot_face_svg.dart';
import '../choice_array.dart';
import 'why_button.dart';

// CTODO refactor
class SpanCard extends StatefulWidget {
  final PangeaMatchState match;
  final Choreographer choreographer;

  const SpanCard({
    super.key,
    required this.match,
    required this.choreographer,
  });

  @override
  State<SpanCard> createState() => SpanCardState();
}

class SpanCardState extends State<SpanCard> {
  bool fetchingData = false;
  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    getSpanDetails();
  }

  @override
  void dispose() {
    TtsController.stop();
    scrollController.dispose();
    super.dispose();
  }

  SpanChoice? get selectedChoice =>
      widget.match.updatedMatch.match.selectedChoice;

  Future<void> getSpanDetails({bool force = false}) async {
    if (widget.match.updatedMatch.isITStart) return;

    if (!mounted) return;
    setState(() {
      fetchingData = true;
    });

    await widget.choreographer.fetchSpanDetails(
      match: widget.match,
      force: force,
    );

    if (mounted) {
      setState(() => fetchingData = false);
    }
  }

  void _onChoiceSelect(int index) {
    widget.match.selectChoice(index);
    setState(
      () => (selectedChoice!.isBestCorrection
          ? BotExpression.gold
          : BotExpression.surprised),
    );
  }

  Future<void> _onAcceptReplacement() async {
    try {
      widget.choreographer.onAcceptReplacement(
        match: widget.match,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        level: SentryLevel.warning,
        data: {
          "match": widget.match.toJson(),
        },
      );
      widget.choreographer.clearMatches(e);
      return;
    }

    _showFirstMatch();
  }

  void _onIgnoreMatch() {
    try {
      widget.choreographer.onIgnoreMatch(match: widget.match);
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        level: SentryLevel.warning,
        data: {
          "match": widget.match.toJson(),
        },
      );
      widget.choreographer.clearMatches(e);
      return;
    }

    _showFirstMatch();
  }

  void _showFirstMatch() {
    if (widget.choreographer.canShowFirstIGCMatch) {
      final igcMatch = widget.choreographer.igc.onShowFirstMatch();
      OverlayUtil.showIGCMatch(
        igcMatch!,
        widget.choreographer,
        context,
      );
    } else {
      MatrixState.pAnyState.closeOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WordMatchContent(
      controller: this,
      scrollController: scrollController,
    );
  }
}

class WordMatchContent extends StatelessWidget {
  final SpanCardState controller;
  final ScrollController scrollController;

  const WordMatchContent({
    required this.controller,
    required this.scrollController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (controller.widget.match.updatedMatch.isITStart) {
      return const SizedBox();
    }

    return SizedBox(
      height: 300.0,
      child: Column(
        children: [
          Expanded(
            child: Scrollbar(
              controller: scrollController,
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    ChoicesArray(
                      isLoading: controller.fetchingData,
                      choices:
                          controller.widget.match.updatedMatch.match.choices
                              ?.map(
                                (e) => Choice(
                                  text: e.value,
                                  color: e.selected ? e.type.color : null,
                                  isGold: e.type.name == 'bestCorrection',
                                ),
                              )
                              .toList(),
                      onPressed: (value, index) =>
                          controller._onChoiceSelect(index),
                      selectedChoiceIndex: controller
                          .widget.match.updatedMatch.match.selectedChoiceIndex,
                      id: controller.widget.match.hashCode.toString(),
                      langCode: MatrixState.pangeaController.languageController
                          .activeL2Code(),
                    ),
                    const SizedBox(height: 12),
                    PromptAndFeedback(controller: controller),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
            ),
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              spacing: 10.0,
              children: [
                Expanded(
                  child: Opacity(
                    opacity: 0.8,
                    child: TextButton(
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all<Color>(
                          Theme.of(context).colorScheme.primary.withAlpha(25),
                        ),
                      ),
                      onPressed: controller._onIgnoreMatch,
                      child: Center(
                        child: Text(L10n.of(context).ignoreInThisText),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Opacity(
                    opacity: controller.selectedChoice != null ? 1.0 : 0.5,
                    child: TextButton(
                      onPressed: controller.selectedChoice != null
                          ? controller._onAcceptReplacement
                          : null,
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all<Color>(
                          (controller.selectedChoice != null
                                  ? controller.selectedChoice!.color
                                  : Theme.of(context).colorScheme.primary)
                              .withAlpha(50),
                        ),
                        // Outline if Replace button enabled
                        side: controller.selectedChoice != null
                            ? WidgetStateProperty.all(
                                BorderSide(
                                  color: controller.selectedChoice!.color,
                                  style: BorderStyle.solid,
                                  width: 2.0,
                                ),
                              )
                            : null,
                      ),
                      child: Text(L10n.of(context).replace),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PromptAndFeedback extends StatelessWidget {
  const PromptAndFeedback({
    super.key,
    required this.controller,
  });

  final SpanCardState controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: controller.widget.match.updatedMatch.isITStart
          ? null
          : const BoxConstraints(minHeight: 75.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (controller.selectedChoice == null && controller.fetchingData)
            const Center(
              child: SizedBox(
                width: 24.0,
                height: 24.0,
                child: CircularProgressIndicator(),
              ),
            ),
          if (controller.selectedChoice != null) ...[
            if (controller.selectedChoice?.feedback != null)
              Text(
                controller.selectedChoice!.feedbackToDisplay(context),
                style: BotStyle.text(context),
              ),
            const SizedBox(height: 8),
            if (controller.selectedChoice?.feedback == null)
              WhyButton(
                onPress: () {
                  if (!controller.fetchingData) {
                    controller.getSpanDetails(force: true);
                  }
                },
                loading: controller.fetchingData,
              ),
          ],
          if (!controller.fetchingData && controller.selectedChoice == null)
            Text(
              controller.widget.match.updatedMatch.match.type.typeName
                  .defaultPrompt(context),
              style: BotStyle.text(context).copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
