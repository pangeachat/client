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

class ActivityStatsMenu extends StatefulWidget {
  final ChatController controller;
  final VoidCallback? onShowDropdown;
  const ActivityStatsMenu(
    this.controller, {
    super.key,
    this.onShowDropdown,
  });

  @override
  State<ActivityStatsMenu> createState() => ActivityStatsMenuState();
}

class ActivityStatsMenuState extends State<ActivityStatsMenu> {
  bool _showDropdown = false;

  double percentVocabComplete = .3;
  //TODO: calculate this percent value by how many are done/how many total to get an actual metric. It's currently set to below .4 so message will only change at 50 new vocab words

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

  void toggleDropdown() {
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
    // Does not count the bot, but only bot activity rooms display non counting message
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
    if (!room.showActivityChatUI) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);

    // Completion status variables
    final bool userComplete = room.hasCompletedActivity;
    final bool activityComplete = room.activityIsFinished;
    bool shouldShowEndForAll = true;
    bool shouldShowImDone = true;

    final analytics = room.liveActivityAnalytics;
    final userId = Matrix.of(context).client.userID ?? '';
    final vocabCount = analytics.uniqueConstructCountForUser(
      userId,
      ConstructTypeEnum.vocab,
    );

    String message = "";

    if (!room.isRoomAdmin) {
      shouldShowEndForAll = false;
    }

    if ((_getAssignedRolesCount() == 1) && (_isBotParticipant() == true)) {
      shouldShowEndForAll = false;
    }

    if (activityComplete) {
      //activity is finished, no buttons
      shouldShowImDone = false;
      shouldShowEndForAll = false;
      message = L10n.of(context).activityComplete;
    } else {
      //activity is ongoing
      if (_getCompletedRolesCount() == 0 ||
          (_getAssignedRolesCount() == 1) && (_isBotParticipant() == true)) {
        //IF nobodys done or you're only playing with the bot,
        //Then it should show tips about your progress and nudge you to continue/end
        if ((percentVocabComplete < .4) && vocabCount < 50) {
          message = L10n.of(context).haventChattedMuch;
        } else {
          message = L10n.of(context).haveChatted;
        }
      } else {
        //user is in group with other users OR someone has wrapped up
        if (userComplete) {
          //user is done but group is ongoing, no buttons
          message = L10n.of(context).userDoneAndWaiting(
            _getCompletedRolesCount(),
            _getAssignedRolesCount(),
          );
        } else {
          //user is not done, buttons are present
          message = L10n.of(context).othersDoneAndWaiting(
            _getCompletedRolesCount(),
            _getAssignedRolesCount(),
          );
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
                          Expanded(
                            child: Wrap(
                              children: [
                                ...room.activityPlan!.vocabList.map(
                                  (vocabWord) => VocabTile(
                                    vocabWord: vocabWord,
                                    isUsed:
                                        true, //TODO: only highlight used vocab words, not all
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

    final screenWidth = MediaQuery.of(context).size.width;
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
    final fontSize = (baseStyle?.fontSize ?? 14) - (screenWidth < 400 ? 4 : 0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        vocabWord,
        style: baseStyle?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: fontSize,
        ),
      ),
    );
  }
}

class ActivityStatsButton extends StatefulWidget {
  final Room room;
  final VoidCallback onToggleDropdown;

  const ActivityStatsButton({
    super.key,
    required this.room,
    required this.onToggleDropdown,
  });

  @override
  State<ActivityStatsButton> createState() => _ActivityStatsButtonState();
}

class _ActivityStatsButtonState extends State<ActivityStatsButton> {
  late StreamSubscription _timelineSubscription;

  @override
  void initState() {
    super.initState();
    // Listen for new messages to refresh stats in real-time
    _timelineSubscription = widget.room.client.onSync.stream.listen((_) {
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
    final screenWidth = MediaQuery.of(context).size.width;
    final baseStyle = theme.textTheme.bodyMedium;
    final double fontSize = (screenWidth < 400) ? 10 : 14;
    final double iconSize = (screenWidth < 400) ? 14 : 18;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: iconSize,
          color: theme.colorScheme.onSurface,
        ),
        const SizedBox(width: 4),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: baseStyle?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
                fontSize: fontSize,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
