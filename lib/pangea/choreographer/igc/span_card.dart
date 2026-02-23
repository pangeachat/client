import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/utils/bot_style.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/choreographer/choreographer.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/span_choice_type_enum.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/widgets/choice_array.dart';
import 'package:fluffychat/pangea/common/widgets/feedback_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SpanCard extends StatefulWidget {
  final Choreographer choreographer;
  final Future Function(String) onFeedbackSubmitted;
  final VoidCallback close;

  const SpanCard({
    super.key,
    required this.choreographer,
    required this.onFeedbackSubmitted,
    required this.close,
  });

  @override
  State<SpanCard> createState() => SpanCardState();
}

class SpanCardState extends State<SpanCard> {
  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.choreographer.igcController.clearActiveMatch();
    });

    scrollController.dispose();
    super.dispose();
  }

  ValueNotifier<PangeaMatchState?> get _activeMatch =>
      widget.choreographer.igcController.activeMatch;

  Future<void> _onChoiceSelect(
    PangeaMatchState match,
    int index,
    PangeaMatchStatusEnum status,
  ) async {
    final choice = match.updatedMatch.match.choices?[index];
    final correct = choice?.isBestCorrection == true;
    final selected = choice?.selected == true;

    match.selectChoice(index);
    setState(() {});

    if (!correct && !selected) return;
    await Future.delayed(
      Duration(milliseconds: 600),
      () => _updateMatch(match, status),
    );
  }

  Future<void> _updateMatch(
    PangeaMatchState match,
    PangeaMatchStatusEnum status,
  ) async {
    try {
      final igc = widget.choreographer.igcController;
      igc.updateMatchStatus(match, status);
      if (!status.isOpen) {
        igc.hasOpenMatches ? igc.setActiveMatch() : widget.close();
      }
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        level: SentryLevel.warning,
        data: {"match": match.toJson()},
      );
      widget.choreographer.clearMatches(e);
      return;
    }
  }

  Future<void> _showFeedbackDialog() async {
    final resp = await showDialog(
      context: context,
      builder: (context) => FeedbackDialog(
        title: L10n.of(context).spanFeedbackTitle,
        onSubmit: (feedback) => Navigator.of(context).pop(feedback),
      ),
    );
    if (resp == null || resp.isEmpty) {
      return;
    }

    await widget.onFeedbackSubmitted(resp);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: widget.choreographer.igcController.matchUpdateStream.stream,
      builder: (context, _) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 300.0),
        child: Column(
          mainAxisSize: .min,
          children: [
            SizedBox(
              height: 40.0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: Theme.of(context).iconTheme.color,
                    onPressed: widget.close,
                  ),
                  const Flexible(
                    child: Center(
                      child: BotFace(
                        width: 32.0,
                        expression: BotExpression.idle,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.flag_outlined),
                    color: Theme.of(context).iconTheme.color,
                    onPressed: _showFeedbackDialog,
                  ),
                ],
              ),
            ),
            ValueListenableBuilder(
              valueListenable: _activeMatch,
              builder: (context, match, _) {
                if (match == null) return SizedBox();
                final isOpen = match.updatedMatch.status.isOpen;
                return Scrollbar(
                  controller: scrollController,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12.0,
                        horizontal: 24.0,
                      ),
                      child: Column(
                        spacing: 12.0,
                        children: isOpen
                            ? [
                                Text(
                                  match.updatedMatch.match.message ??
                                      match.updatedMatch.match.type
                                          .defaultPrompt(context),
                                  style: BotStyle.text(context),
                                ),
                                ChoicesArray(
                                  isLoading: false,
                                  choices: match.updatedMatch.match.choices
                                      ?.map(
                                        (e) => Choice(
                                          text: e.value,
                                          color: e.selected
                                              ? e.type.color
                                              : null,
                                          isGold: e.type.isSuggestion,
                                        ),
                                      )
                                      .toList(),
                                  onPressed: (value, index) => _onChoiceSelect(
                                    match,
                                    index,
                                    PangeaMatchStatusEnum.accepted,
                                  ),
                                  selectedChoiceIndex: match
                                      .updatedMatch
                                      .match
                                      .selectedChoiceIndex,
                                  id: match.hashCode.toString(),
                                  langCode: MatrixState
                                      .pangeaController
                                      .userController
                                      .userL2Code!,
                                ),
                              ]
                            : [
                                Row(
                                  spacing: 16.0,
                                  mainAxisAlignment: .center,
                                  children: [
                                    Wrap(
                                      spacing: 8.0,
                                      runSpacing: 4.0,
                                      crossAxisAlignment: .center,
                                      children: [
                                        Text(
                                          match.originalMatch.match.errorSpan,
                                        ),
                                        Icon(Icons.arrow_forward, size: 16.0),
                                        Text(
                                          match
                                                  .updatedMatch
                                                  .match
                                                  .selectedChoice
                                                  ?.value ??
                                              L10n.of(context).nothingFound,
                                        ),
                                      ],
                                    ),
                                    IconButton(
                                      icon: Icon(Symbols.undo),
                                      onPressed: () => _updateMatch(
                                        match,
                                        PangeaMatchStatusEnum.undo,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
