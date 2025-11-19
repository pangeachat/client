import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_chat/activity_vocab_widget.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_details_row.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_analytics_model.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class ActivityStatsMenu extends StatefulWidget {
  final ChatController controller;
  const ActivityStatsMenu(
    this.controller, {
    super.key,
  });

  @override
  State<ActivityStatsMenu> createState() => ActivityStatsMenuState();
}

class ActivityStatsMenuState extends State<ActivityStatsMenu> {
  ActivitySummaryAnalyticsModel? analytics;
  Room get room => widget.controller.room;

  StreamSubscription? _analyticsSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateUsedVocab();
    });

    _analyticsSubscription = widget
        .controller.pangeaController.getAnalytics.analyticsStream.stream
        .listen((_) {
      _updateUsedVocab();
    });
  }

  @override
  void dispose() {
    _analyticsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _updateUsedVocab() async {
    final analytics = await room.getActivityAnalytics();
    if (mounted) {
      setState(() => this.analytics = analytics);
    }
  }

  int _getAssignedRolesCount() {
    final assignedRoles = room.assignedRoles;
    if (assignedRoles == null) return 0;
    final nonBotRoles = assignedRoles.values.where(
      (role) => role.userId != BotName.byEnvironment,
    );

    return nonBotRoles.length;
  }

  bool _isBotParticipant() {
    final assignedRoles = room.assignedRoles;
    if (assignedRoles == null) return false;
    return assignedRoles.values.any(
      (role) => role.userId == BotName.byEnvironment,
    );
  }

  Future<void> _finishActivity({bool forAll = false}) async {
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        forAll
            ? await room.finishActivityForAll()
            : await room.finishActivity();
        if (mounted) {
          widget.controller.toggleShowDropdown();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!room.showActivityChatUI) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    // Completion status variables
    final bool userComplete = room.hasCompletedRole;
    final bool activityComplete = room.isActivityFinished;
    bool shouldShowEndForAll = true;
    bool shouldShowImDone = true;

    if (!room.isRoomAdmin) {
      shouldShowEndForAll = false;
    }

    //dont need endforall if only w bot
    if ((_getAssignedRolesCount() == 1) && (_isBotParticipant() == true)) {
      shouldShowEndForAll = false;
    }

    if (activityComplete) {
      //activity is finished, no buttons
      shouldShowImDone = false;
      shouldShowEndForAll = false;
    }

    return ValueListenableBuilder(
      valueListenable:
          widget.controller.activityController.showActivityDropdown,
      builder: (context, showDropdown, child) {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: showDropdown ? 0 : null,
          child: Column(
            children: [
              ClipRect(
                child: AnimatedAlign(
                  duration: FluffyThemes.animationDuration,
                  curve: Curves.easeInOut,
                  heightFactor: showDropdown ? 1.0 : 0.0,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      if (details.delta.dy < -2) {
                        widget.controller.toggleShowDropdown();
                      }
                    },
                    child: child,
                  ),
                ),
              ),
              if (showDropdown)
                Expanded(
                  child: GestureDetector(
                    onTap: widget.controller.toggleShowDropdown,
                    child: Container(color: Colors.black.withAlpha(100)),
                  ),
                ),
            ],
          ),
        );
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
        ),
        padding: const EdgeInsets.all(12.0),
        child: Column(
          spacing: 12.0,
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              spacing: 8.0,
              mainAxisSize: MainAxisSize.min,
              children: [
                ActivitySessionDetailsRow(
                  icon: Symbols.radar,
                  iconSize: 16.0,
                  child: Text(
                    room.activityPlan!.learningObjective,
                    style: const TextStyle(fontSize: 12.0),
                  ),
                ),
                ActivitySessionDetailsRow(
                  icon: Symbols.dictionary,
                  iconSize: 16.0,
                  child: ActivityVocabWidget(
                    key: ValueKey(
                      "activity-stats-${room.activityPlan!.activityId}",
                    ),
                    vocab: room.activityPlan!.vocab,
                    langCode: room.activityPlan!.req.targetLanguage,
                    targetId: "activity-vocab",
                    usedVocab: widget.controller.activityController.usedVocab,
                  ),
                ),
              ],
            ),
            if (!userComplete) ...[
              Text(
                L10n.of(context).activityDropdownDesc,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (shouldShowEndForAll)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 8.0,
                    ),
                    side: BorderSide(
                      color: theme.colorScheme.secondaryContainer,
                      width: 2,
                    ),
                    foregroundColor: theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.surface,
                  ),
                  onPressed: () => _finishActivity(forAll: true),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        L10n.of(context).endForAll,
                        style: TextStyle(
                          fontSize: isColumnMode ? 16.0 : 12.0,
                        ),
                      ),
                    ],
                  ),
                ),
              if (shouldShowImDone)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 8.0,
                    ),
                  ),
                  onPressed: _finishActivity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        L10n.of(context).endActivity,
                        style: TextStyle(
                          fontSize: isColumnMode ? 16.0 : 12.0,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
