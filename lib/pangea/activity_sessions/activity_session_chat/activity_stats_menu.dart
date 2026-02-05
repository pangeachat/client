import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_chat/activity_vocab_widget.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_details_row.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class ActivityStatsMenu extends StatelessWidget {
  final ChatController controller;
  const ActivityStatsMenu(this.controller, {super.key});

  int _getAssignedRolesCount() {
    final assignedRoles = controller.room.assignedRoles;
    if (assignedRoles == null) return 0;
    final nonBotRoles = assignedRoles.values.where(
      (role) => role.userId != BotName.byEnvironment,
    );

    return nonBotRoles.length;
  }

  bool _isBotParticipant() {
    final assignedRoles = controller.room.assignedRoles;
    if (assignedRoles == null) return false;
    return assignedRoles.values.any(
      (role) => role.userId == BotName.byEnvironment,
    );
  }

  Future<void> _finishActivity(
    BuildContext context, {
    bool forAll = false,
  }) async {
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        forAll
            ? await controller.room.finishActivityForAll()
            : await controller.room.finishActivity();
        controller.toggleShowDropdown();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.room.showActivityChatUI) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    // Completion status variables
    final bool userComplete =
        controller.room.hasPickedRole && controller.room.hasCompletedRole;

    final bool activityComplete = controller.room.isActivityFinished;
    bool shouldShowEndForAll = true;
    bool shouldShowImDone = true;

    if (!controller.room.isRoomAdmin) {
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
      valueListenable: controller.activityController.showActivityDropdown,
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
                        controller.toggleShowDropdown();
                      }
                    },
                    child: child,
                  ),
                ),
              ),
              if (showDropdown)
                Expanded(
                  child: GestureDetector(
                    onTap: controller.toggleShowDropdown,
                    child: Container(color: Colors.black.withAlpha(100)),
                  ),
                ),
            ],
          ),
        );
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(color: theme.colorScheme.surface),
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
                    controller.room.activityPlan!.learningObjective,
                    style: const TextStyle(fontSize: 12.0),
                  ),
                ),
                ActivitySessionDetailsRow(
                  icon: Symbols.dictionary,
                  iconSize: 16.0,
                  child: ActivityVocabWidget(
                    key: ValueKey(
                      "activity-stats-${controller.room.activityPlan!.activityId}",
                    ),
                    vocab: controller.room.activityPlan!.vocab,
                    langCode: controller.room.activityPlan!.req.targetLanguage,
                    targetId: "activity-vocab",
                    usedVocab: controller.activityController.usedVocab,
                    activityLangCode:
                        controller.room.activityPlan!.req.targetLanguage,
                  ),
                ),
              ],
            ),
            if (!userComplete && (shouldShowImDone || shouldShowEndForAll)) ...[
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
                  onPressed: () => _finishActivity(context, forAll: true),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        L10n.of(context).endForAll,
                        style: TextStyle(fontSize: isColumnMode ? 16.0 : 12.0),
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
                  onPressed: () => _finishActivity(context),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        L10n.of(context).endActivity,
                        style: TextStyle(fontSize: isColumnMode ? 16.0 : 12.0),
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
