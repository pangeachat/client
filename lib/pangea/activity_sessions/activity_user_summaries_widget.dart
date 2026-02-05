import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_participant_indicator.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_response_model.dart';
import 'package:fluffychat/widgets/avatar.dart';

class ActivityUserSummaries extends StatelessWidget {
  final ChatController controller;

  const ActivityUserSummaries({super.key, required this.controller});

  Room get room => controller.room;

  @override
  Widget build(BuildContext context) {
    final summary = room.activitySummary?.summary;
    if (summary == null) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        spacing: 4.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 4.0,
            ),
            child: Center(
              child: Material(
                color: Theme.of(context).colorScheme.surface.withAlpha(128),
                borderRadius: BorderRadius.circular(AppConfig.borderRadius / 3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: Column(
                    spacing: 4.0,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(L10n.of(context).activityFinishedMessage),
                      Text(summary.summary, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8.0)),
          ButtonControlledCarouselView(
            summary: summary,
            controller: controller,
          ),
        ],
      ),
    );
  }
}

class ButtonControlledCarouselView extends StatelessWidget {
  final ActivitySummaryResponseModel summary;
  final ChatController controller;
  const ButtonControlledCarouselView({
    super.key,
    required this.summary,
    required this.controller,
  });

  void _scrollToUser(ActivityRoleModel role, int index, double cardWidth) {
    controller.activityController.highlightRole(role);

    final scrollController = controller.activityController.carouselController;

    if (!scrollController.hasClients) return;

    const spacing = 5.0;
    final itemExtent = cardWidth + spacing;

    final viewportWidth = scrollController.position.viewportDimension;

    final itemCenter = (index * itemExtent) + (cardWidth / 2);

    final targetOffset = itemCenter - (viewportWidth / 2);

    final clampedOffset = targetOffset.clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent,
    );

    scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final superlatives = room.activitySummary?.analytics
        ?.generateSuperlatives();
    final availableRoles = room.activityPlan!.roles;
    final assignedRoles = room.assignedRoles ?? {};
    final userSummaries = summary.participants
        .where(
          (p) => assignedRoles.values.any(
            (role) => role.userId == p.participantId,
          ),
        )
        .toList();

    final isColumnMode = FluffyThemes.isColumnMode(context);

    if (userSummaries.isEmpty) {
      return const SizedBox();
    }

    final cardWidth = isColumnMode ? 400.0 : 350.0;

    return Column(
      children: [
        SizedBox(
          height: 270.0,
          child: ListView.builder(
            key: PageStorageKey('summaries-carousel-${room.id}'),
            shrinkWrap: true,
            controller: controller.activityController.carouselController,
            scrollDirection: Axis.horizontal,
            itemCount: userSummaries.length,
            itemBuilder: (context, i) {
              final p = userSummaries[i];
              final user = room.getParticipants().firstWhereOrNull(
                (u) => u.id == p.participantId,
              );
              final userRole = assignedRoles.values.firstWhere(
                (role) => role.userId == p.participantId,
              );
              return Container(
                width: cardWidth,
                margin: i == userSummaries.length - 1
                    ? null
                    : const EdgeInsets.only(right: 5.0),
                padding: const EdgeInsets.all(12.0),
                decoration: ShapeDecoration(
                  color: Color.alphaBlend(
                    Theme.of(context).colorScheme.surface.withAlpha(70),
                    AppConfig.gold,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Column(
                  spacing: 4.0,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      spacing: 10.0,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Avatar(
                          name: p.participantId.localpart,
                          mxContent: user?.avatarUrl,
                          size: 40,
                        ),
                        Flexible(
                          child: Text(
                            "${userRole.role ?? L10n.of(context).participant} | ${user?.calcDisplayname() ?? p.participantId.localpart}",
                            style: const TextStyle(fontSize: 14.0),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Flexible(
                      child: _SummaryText(
                        text: p.displayFeedback(
                          user?.calcDisplayname() ??
                              p.participantId.localpart ??
                              p.participantId,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              Text(
                                p.cefrLevel,
                                style: const TextStyle(fontSize: 14.0),
                              ),
                              //const SizedBox(width: 8),
                              if (superlatives != null &&
                                  (superlatives['vocab']!.contains(
                                    p.participantId,
                                  ))) ...[
                                const SuperlativeTile(icon: Symbols.dictionary),
                              ],
                              if (superlatives != null &&
                                  (superlatives['grammar']!.contains(
                                    p.participantId,
                                  ))) ...[
                                const SuperlativeTile(
                                  icon: Symbols.toys_and_games,
                                ),
                              ],
                              if (superlatives != null &&
                                  (superlatives['xp']!.contains(
                                    p.participantId,
                                  ))) ...[
                                const SuperlativeTile(icon: Icons.star),
                              ],
                              if (p.superlatives.isNotEmpty) ...[
                                Text(
                                  p.superlatives.first,
                                  style: const TextStyle(fontSize: 14.0),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 125.0,
          child: ValueListenableBuilder(
            valueListenable: controller.activityController.highlightedRole,
            builder: (context, highlightedRole, _) {
              return ListView.builder(
                shrinkWrap: true,
                scrollDirection: Axis.horizontal,
                itemCount: userSummaries.length,
                itemBuilder: (context, index) {
                  final p = userSummaries[index];
                  final user = room.getParticipants().firstWhereOrNull(
                    (u) => u.id == p.participantId,
                  );
                  final userRole = assignedRoles.values.firstWhere(
                    (role) => role.userId == p.participantId,
                  );
                  final userRoleInfo = availableRoles[userRole.id]!;
                  return SizedBox(
                    width: 100.0,
                    height: 125.0,
                    child: Center(
                      child: ActivityParticipantIndicator(
                        name: userRoleInfo.name,
                        userId: p.participantId,
                        user: user,
                        borderRadius: BorderRadius.circular(4),
                        selected: highlightedRole?.id == userRole.id,
                        onTap: () => _scrollToUser(userRole, index, cardWidth),
                        room: controller.room,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class SuperlativeTile extends StatelessWidget {
  final IconData icon;

  const SuperlativeTile({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurface),
        const SizedBox(width: 2),
        const Text("1st", style: TextStyle(fontSize: 14.0)),
      ],
    );
  }
}

class _SummaryText extends StatefulWidget {
  final String text;
  const _SummaryText({required this.text});

  @override
  State<_SummaryText> createState() => _SummaryTextState();
}

class _SummaryTextState extends State<_SummaryText> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Text(widget.text, style: const TextStyle(fontSize: 14.0)),
      ),
    );
  }
}
