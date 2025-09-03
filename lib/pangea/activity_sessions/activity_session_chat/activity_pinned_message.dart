import 'dart:async';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/bot/utils/bot_name.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

class ActivityPinnedMessage extends StatefulWidget {
  final ChatController controller;
  final VoidCallback? onShowDropdown;
  const ActivityPinnedMessage(
    this.controller, {
    super.key,
    this.onShowDropdown,
  });

  @override
  State<ActivityPinnedMessage> createState() => ActivityPinnedMessageState();
}

class ActivityPinnedMessageState extends State<ActivityPinnedMessage> {
  bool _showDropdown = false;

  Room get room => widget.controller.room;

  @override
  void initState() {
    super.initState();
    // Register the callback to show dropdown when called from parent
    if (widget.onShowDropdown != null) {
      widget.controller.activityPinnedShowDropdown = toggleDropdown;
    }
  }

  void _setShowDropdown(bool value) {
    if (value != _showDropdown) {
      setState(() {
        _showDropdown = value;
      });
    }
  }

  //public methods to show/hide dropdown from external widgets (activity button)
  void toggleDropdown() {
    //_setShowDropdown(true);
    if (_showDropdown) {
      _setShowDropdown(false);
    } else {
      _setShowDropdown(true);
    }
  }

  int _getAssignedRolesCount() {
    final assignedRoles = room.assignedRoles;
    if (assignedRoles == null) return 0;

    // Filter out the bot from the count, similar to activityIsFinished logic
    //This is a workaround for the Bot not officially wrapping up, if it does in the future this can be taken out and just return the count
    final nonBotRoles = assignedRoles.values.where(
      (role) => role.userId != BotName.byEnvironment,
    );

    return nonBotRoles.length;
  }

  int _getCompletedRolesCount() {
    final assignedRoles = room.assignedRoles;
    if (assignedRoles == null) return 0;

    // Filter out the bot and count only finished non-bot roles
    return assignedRoles.values
        .where(
          (role) => role.userId != BotName.byEnvironment && role.isFinished,
        )
        .length;
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
          _setShowDropdown(false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      "ActivityPinnedMessage: showActivityChatUI = ${room.showActivityChatUI}",
    );
    debugPrint(
      "ActivityPinnedMessage: activityPlan = ${room.activityPlan != null ? 'exists' : 'null'}",
    );

    if (!room.showActivityChatUI) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    // Completion status variables
    final bool userComplete = room.hasCompletedActivity;
    final bool activityComplete = room.activityIsFinished;
    final bool userHasRole = (room.ownRole != null);
    bool shouldShowEndForAll = true;
    bool shouldShowImDone = true;
    debugPrint(
      "assigned roles: ${_getAssignedRolesCount()} bot participant? ${_isBotParticipant()}",
    );

    String message = "";

    if (!room.isRoomAdmin) {
      shouldShowEndForAll = false;
    }

    if (!userHasRole) {
      shouldShowImDone = false;
      shouldShowEndForAll = false;
      if (room.remainingRoles == 0) {
        //user has no role yet and there are none left, can see message but no buttons
        message =
            "There are no open roles in this activity, but feel free to stay and watch. Or, if you'd like to participate, you can make another activity and invite your friends!";
      } else {
        //user has no role yet but there are some left, can see message but no buttons
        message =
            "There are ${room.remainingRoles} roles left, join one if you'd like to participate!";
      }
    } else if (activityComplete) {
      //activity is finished, no buttons
      shouldShowImDone = false;
      shouldShowEndForAll = false;
      message =
          "This activity has been completed. See the activity summary below!";
    } else {
      //activity is ongoing
      if ((_getAssignedRolesCount() == 1) && (_isBotParticipant() == true)) {
        //user is in room with only bot, controls wrapping up, should only show one wrap up button
        shouldShowEndForAll = false;
        message =
            "If you feel like you've completed your objective, wrap up to finish the activity and we'll generate you a summary in the chat!";
      } else {
        //user is in group with other users
        if (userComplete) {
          //user is done but group is ongoing, no buttons
          message =
              "You and ${_getCompletedRolesCount()}/${_getAssignedRolesCount()} participants have wrapped up. Wait for everyone to finish, and we'll generate you a summary in the chat! \n\nIf you'd like to rejoin the conversation, click 'Continue' in the chat.";
        } else {
          //user is not done, buttons are present
          message =
              "${_getCompletedRolesCount()}/${_getAssignedRolesCount()} are done. Have you completed your objective?";
        }
      }
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: _showDropdown ? 0 : null,
      child: Column(
        children: [
          AnimatedContainer(
            duration: FluffyThemes.animationDuration,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
            ),
            child: const SizedBox.shrink(),
          ),
          ClipRect(
            child: AnimatedAlign(
              duration: FluffyThemes.animationDuration,
              curve: Curves.easeInOut,
              heightFactor: _showDropdown ? 1.0 : 0.0,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onPanUpdate: (details) {
                  // Detect upward swipe
                  if (details.delta.dy < -2) {
                    _setShowDropdown(false);
                  }
                },
                onTap: () {},
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 16.0,
                  ),
                  child: Column(
                    spacing: 12.0,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Table-like layout with 3 rows
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Symbols.radar,
                            size: 20,
                            color: theme.colorScheme.onSurface,
                          ),
                          const SizedBox(width: 12.0),
                          Expanded(
                            child: Text(
                              room.activityPlan!.learningObjective,
                              textAlign: TextAlign.left,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Symbols.dictionary,
                            size: 20,
                            color: theme.colorScheme.onSurface,
                          ),
                          const SizedBox(width: 12.0),
                          // Expanded(
                          //   child: Text(
                          //     room.activityPlan!.vocabString,
                          //     textAlign: TextAlign.left,
                          //     style: theme.textTheme.bodyMedium,
                          //   ),
                          // ),
                          Expanded(
                            child: Wrap(
                              children: [
                                ...room.activityPlan!.vocabList.map(
                                  (vocabWord) => VocabTile(
                                    vocabWord: vocabWord,
                                    isUsed:
                                        true, //room.liveActivityAnalytics.hasUsedVocab(vocabWord),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                      userComplete
                          ? const SizedBox.shrink()
                          : Column(
                              spacing: 12.0,
                              children: [
                                if (shouldShowEndForAll)
                                  //endForAll shows when the user has a role and it's not a room with only the bot (don't need two buttons if they both do the same thing)
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12.0,
                                          vertical: 8.0,
                                        ),
                                        side: BorderSide(
                                          color: theme
                                              .colorScheme.secondaryContainer,
                                          width: 2,
                                        ),
                                        foregroundColor:
                                            theme.colorScheme.primary,
                                        backgroundColor:
                                            theme.colorScheme.surface,
                                      ),
                                      onPressed: () =>
                                          _finishActivity(forAll: true),
                                      child: Text(
                                        L10n.of(context).endForAll,
                                        style: TextStyle(
                                          fontSize: isColumnMode ? 16.0 : 12.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                SizedBox(
                                  width: double.infinity,
                                  child: (shouldShowImDone)
                                      ? ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12.0,
                                              vertical: 8.0,
                                            ),
                                            // foregroundColor:
                                            //     theme.colorScheme.onSecondary,
                                            // backgroundColor:
                                            //     theme.colorScheme.secondary,
                                          ),
                                          onPressed: _finishActivity,
                                          child: Text(
                                            L10n.of(context).endActivityTitle,
                                            style: TextStyle(
                                              fontSize:
                                                  isColumnMode ? 16.0 : 12.0,
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_showDropdown)
            Expanded(
              child: GestureDetector(
                onTap: () => _setShowDropdown(false),
                child: Container(color: Colors.black.withAlpha(100)),
              ),
            ),
        ],
      ),
    );
  }
}

class VocabTile extends StatelessWidget {
  final String vocabWord;
  final bool isUsed;

  const VocabTile({
    super.key,
    required this.vocabWord,
    required this.isUsed,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isUsed ? AppConfig.goldLight.withAlpha(100) : Colors.transparent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        vocabWord,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
      ),
    );
  }
}

class ActivityStatsRow extends StatefulWidget {
  final Room room;
  final VoidCallback onToggleDropdown;

  const ActivityStatsRow({
    super.key,
    required this.room,
    required this.onToggleDropdown,
  });

  @override
  State<ActivityStatsRow> createState() => _ActivityStatsRowState();
}

class _ActivityStatsRowState extends State<ActivityStatsRow> {
  late StreamSubscription _timelineSubscription;

  @override
  void initState() {
    super.initState();
    // Listen for new messages to refresh stats in real-time
    _timelineSubscription = widget.room.onUpdate.stream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timelineSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use live analytics instead of summary analytics
    final analytics = widget.room.liveActivityAnalytics;


    final userId = Matrix.of(context).client.userID ?? '';
    final vocabCount = analytics.uniqueConstructCountForUser(
      userId,
      ConstructTypeEnum.vocab,
    );
    final grammarCount = analytics.uniqueConstructCountForUser(
      userId,
      ConstructTypeEnum.morph,
    );
    final xpCount = analytics.totalXPForUser(userId);

    debugPrint(
      "userID: $userId, vocabCount: $vocabCount, grammarCount: $grammarCount, xpCount: $xpCount",
    );

    // Always show the row, even with zero data
    return Container(
      width: 350,
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onToggleDropdown,
        child: Container(
          decoration: BoxDecoration(
            color: AppConfig.goldLight.withAlpha(100),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(
                context: context,
                icon: Icons.radar,
                value: "$xpCount XP",
                label: "XP",
              ),
              _buildStatItem(
                context: context,
                icon: Symbols.dictionary,
                value: "$vocabCount",
                label: "Vocab",
              ),
              _buildStatItem(
                context: context,
                icon: Symbols.toys_and_games,
                value: "$grammarCount",
                label: "Grammar",
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required BuildContext context,
    required IconData icon,
    required String value,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 18,
          color: theme.colorScheme.onSurface,
        ),
        const SizedBox(width: 4),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
