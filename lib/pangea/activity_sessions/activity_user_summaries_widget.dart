import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_participant_indicator.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_analytics_model.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_response_model.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

class ActivityUserSummaries extends StatelessWidget {
  final ChatController controller;

  const ActivityUserSummaries({
    super.key,
    required this.controller,
  });

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
          Text(
            L10n.of(context).activityFinishedMessage,
          ),
          Text(
            summary.summary,
            textAlign: TextAlign.center,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(
              vertical: 8.0,
            ),
          ),
          ButtonControlledCarouselView(
            summary: summary,
            controller: controller,
          ),
          // Row(
          //   mainAxisSize: MainAxisSize.min,
          //   children: userSummaries.map((p) {
          //     final user = room.getParticipants().firstWhereOrNull(
          //           (u) => u.id == p.participantId,
          //         );
          //     final userRole = assignedRoles.values.firstWhere(
          //       (role) => role.userId == p.participantId,
          //     );
          //     final userRoleInfo = availableRoles[userRole.id]!;
          //     return ActivityParticipantIndicator(
          //       availableRole: userRoleInfo,
          //       assignedRole: userRole,
          //       avatarUrl:
          //           userRoleInfo.avatarUrl ?? user?.avatarUrl?.toString(),
          //       borderRadius: BorderRadius.circular(4),
          //       selected: controller.highlightedRole?.id == userRole.id,
          //       onTap: () => controller.highlightRole(userRole),
          //     );
          //   }).toList(),
          // ),
        ],
      ),
    );
  }
}

class ButtonControlledCarouselView extends StatefulWidget {
  final ActivitySummaryResponseModel summary;
  final ChatController controller;
  const ButtonControlledCarouselView({
    super.key,
    required this.summary,
    required this.controller,
  });

  @override
  State<ButtonControlledCarouselView> createState() =>
      _ButtonControlledCarouselViewState();
}

class _ButtonControlledCarouselViewState
    extends State<ButtonControlledCarouselView> {
  ActivitySummaryAnalyticsModel? analytics;
  Room? room;

  Future<void> loadSuperlatives() async {
    final loadedAnalytics = await room!.getActivityAnalytics();
    if (mounted) {
      setState(() {
        analytics = loadedAnalytics;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint("InitState");
    room = widget.controller.room;
    loadSuperlatives();
  }

  @override
  Widget build(BuildContext context) {
    // final room = widget.controller.room;
    debugPrint("Rebuilding, analytics is null? ${analytics == null}");
    final availableRoles = room!.activityPlan!.roles;
    final assignedRoles = room!.assignedRoles ?? {};
    final userSummaries = widget.summary.participants
        .where(
          (p) => assignedRoles.values.any(
            (role) => role.userId == p.participantId,
          ),
        )
        .toList();

    return Column(
      children: [
        SizedBox(
          height: 230.0,
          child: ListView(
            shrinkWrap: true,
            controller: widget.controller.carouselController,
            scrollDirection: Axis.horizontal,
            children: userSummaries.mapIndexed((i, p) {
              final user = room!.getParticipants().firstWhereOrNull(
                    (u) => u.id == p.participantId,
                  );
              final userRole = assignedRoles.values.firstWhere(
                (role) => role.userId == p.participantId,
              );
              return Container(
                width: 350.0,
                margin: const EdgeInsets.only(right: 5.0),
                padding: const EdgeInsets.all(12.0),
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      width: 0.10,
                      color: Theme.of(context).colorScheme.outline,
                    ),
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
                            style: const TextStyle(
                              fontSize: 12.0,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Text(
                          p.feedback,
                          style: const TextStyle(fontSize: 12.0),
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
                            //crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                p.cefrLevel,
                                style: const TextStyle(
                                  color: AppConfig.yellowDark,
                                  fontSize: 12.0,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (analytics != null) ...[
                                SuperlativeTile(
                                  icon: Symbols.dictionary,
                                  show: analytics!.superlatives['vocab']
                                          ?.contains(
                                        p.participantId,
                                      ) ??
                                      false,
                                ),
                                SuperlativeTile(
                                  icon: Symbols.toys_and_games,
                                  show: analytics!.superlatives['grammar']
                                          ?.contains(
                                        p.participantId,
                                      ) ??
                                      false,
                                ),
                              ],
                              if (p.superlatives.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Text(
                                  p.superlatives.first,
                                  style: const TextStyle(fontSize: 12.0),
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
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: userSummaries.mapIndexed((i, p) {
            final user = room!.getParticipants().firstWhereOrNull(
                  (u) => u.id == p.participantId,
                );
            final userRole = assignedRoles.values.firstWhere(
              (role) => role.userId == p.participantId,
            );
            final userRoleInfo = availableRoles[userRole.id]!;
            return ActivityParticipantIndicator(
              name: userRoleInfo.name,
              userId: p.participantId,
              avatarUrl: userRoleInfo.avatarUrl ?? user?.avatarUrl?.toString(),
              borderRadius: BorderRadius.circular(4),
              selected: widget.controller.highlightedRole?.id == userRole.id,
              onTap: () {
                widget.controller.highlightRole(userRole);
                widget.controller.carouselController.jumpTo(i * 250.0);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}

class SuperlativeTile extends StatelessWidget {
  final IconData icon;
  final bool show;

  const SuperlativeTile({
    super.key,
    required this.icon,
    required this.show,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppConfig.gold),
        const SizedBox(width: 2),
        const Text(
          "1st",
          style: TextStyle(
            color: AppConfig.gold,
            fontSize: 12.0,
          ),
        ),
      ],
    );
  }
}
