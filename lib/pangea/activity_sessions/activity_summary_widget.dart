// ignore_for_file: implementation_imports

import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_html/flutter_html.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/markdown.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_participant_list.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_chat/activity_vocab_widget.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_details_row.dart';
import 'package:fluffychat/pangea/common/widgets/url_image_widget.dart';

class ActivitySummary extends StatelessWidget {
  final ActivityPlanModel activity;
  final Room? room;
  final Room? course;
  final Map<String, ActivityRoleModel> assignedRoles;

  final bool showInstructions;
  final VoidCallback toggleInstructions;

  final Function(String)? onTapParticipant;
  final bool Function(String)? canSelectParticipant;
  final bool Function(String)? isParticipantSelected;
  final bool Function(String)? isParticipantShimmering;
  final double Function(ActivityRoleModel?)? getParticipantOpacity;

  final ValueNotifier<Set<String>>? usedVocab;

  final bool inChat;

  const ActivitySummary({
    super.key,
    required this.activity,
    required this.showInstructions,
    required this.toggleInstructions,
    required this.assignedRoles,
    this.usedVocab,
    this.onTapParticipant,
    this.canSelectParticipant,
    this.isParticipantSelected,
    this.isParticipantShimmering,
    this.getParticipantOpacity,
    this.room,
    this.course,
    this.inChat = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.all(12.0),
        constraints: const BoxConstraints(
          maxWidth: FluffyThemes.columnWidth * 1.5,
        ),
        child: Column(
          spacing: 4.0,
          children: [
            (!inChat || !AppConfig.useActivityImageAsChatBackground)
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      return ImageByUrl(
                        imageUrl: activity.imageURL,
                        width: min(
                          constraints.maxWidth,
                          MediaQuery.sizeOf(context).height * 0.5,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      );
                    },
                  )
                : const SizedBox.shrink(),
            ActivityParticipantList(
              activity: activity,
              room: room,
              assignedRoles: assignedRoles,
              course: course,
              onTap: onTapParticipant,
              canSelect: canSelectParticipant,
              isSelected: isParticipantSelected,
              isShimmering: isParticipantShimmering,
              getOpacity: getParticipantOpacity,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withAlpha(128),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12.0),
                    hoverColor: theme.colorScheme.surfaceTint.withAlpha(55),
                    onTap: toggleInstructions,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        spacing: 4.0,
                        children: [
                          Text(
                            activity.description,
                            style: theme.textTheme.bodyMedium,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              spacing: 4.0,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  L10n.of(context).details,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                Icon(
                                  showInstructions
                                      ? Icons.arrow_drop_up
                                      : Icons.arrow_drop_down,
                                  size: 22.0,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (showInstructions)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            spacing: 8.0,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                activity.req.mode,
                                style: theme.textTheme.bodyMedium,
                              ),
                              Row(
                                spacing: 4.0,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.school, size: 12.0),
                                  Text(
                                    activity.req.cefrLevel.string,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          ActivitySessionDetailsRow(
                            icon: Symbols.target,
                            iconSize: 16.0,
                            child: Text(
                              activity.learningObjective,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          ActivitySessionDetailsRow(
                            icon: Symbols.steps,
                            iconSize: 16.0,
                            child: Html(
                              data: markdown(
                                activity.instructions
                                    .replaceAll(RegExp('\n+'), '\n')
                                    .replaceAll('---', ''),
                              ),
                              style: {
                                "body": Style(
                                  margin: Margins.all(0),
                                  padding: HtmlPaddings.all(0),
                                  fontSize: FontSize(
                                    theme.textTheme.bodyMedium!.fontSize!,
                                  ),
                                ),
                              },
                            ),
                          ),
                          ActivitySessionDetailsRow(
                            icon: Symbols.dictionary,
                            iconSize: 16.0,
                            child: ActivityVocabWidget(
                              key: ValueKey(
                                "activity-summary-${activity.activityId}",
                              ),
                              vocab: activity.vocab,
                              langCode: activity.req.targetLanguage,
                              targetId: "activity-summary-vocab",
                              usedVocab: usedVocab,
                              activityLangCode: activity.req.targetLanguage,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InlineEllipsisText extends StatelessWidget {
  final String text;
  final int? maxLines;
  final TextStyle? style;
  final WidgetSpan trailing;
  final double trailingWidth;

  const InlineEllipsisText({
    super.key,
    required this.text,
    required this.trailing,
    required this.trailingWidth,
    this.maxLines,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    final span = TextSpan(text: text, style: effectiveStyle);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: span,
          maxLines: maxLines,
          textDirection: TextDirection.ltr,
          ellipsis: '…',
        );

        tp.layout(maxWidth: constraints.maxWidth);
        String truncated = text;
        if (tp.didExceedMaxLines && maxLines != null) {
          // Find cutoff point where text fits
          final pos = tp.getPositionForOffset(
            Offset(
              constraints.maxWidth - trailingWidth,
              tp.preferredLineHeight * maxLines!,
            ),
          );
          final endIndex = tp.getOffsetBefore(pos.offset) ?? text.length;
          truncated = '${text.substring(0, endIndex).trimRight()}…';
        }

        tp.dispose();
        return RichText(
          text: TextSpan(
            children: [
              TextSpan(text: truncated, style: effectiveStyle),
              trailing, // always visible
            ],
          ),
          maxLines: maxLines,
          overflow: TextOverflow.clip, // prevent extra wrapping
        );
      },
    );
  }
}
