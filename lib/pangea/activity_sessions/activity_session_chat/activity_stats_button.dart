import 'dart:async';

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class ActivityStatsButton extends StatefulWidget {
  final ChatController controller;

  const ActivityStatsButton({
    super.key,
    required this.controller,
  });

  @override
  State<ActivityStatsButton> createState() => _ActivityStatsButtonState();
}

class _ActivityStatsButtonState extends State<ActivityStatsButton> {
  late StreamSubscription _syncSubscription;
  int vocabCount = 0;
  int xpCount = 0;
  int grammarCount = 0;

  @override
  void initState() {
    super.initState();
    // Listen for new messages to refresh stats in real-time
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateAllCounts(),
    );
    // _syncSubscription = widget.controller.room.client.onSync.stream.listen((_) {
    //   _updateAllCounts();
    // });
  }

  @override
  void dispose() {
    _syncSubscription.cancel();
    super.dispose();
  }

  Future<void> _updateAllCounts() async {
    final analytics = await widget.controller.room.getActivityAnalytics();
    final userId = Matrix.of(context).client.userID ?? '';
    if (mounted) {
      setState(() {
        vocabCount = analytics.uniqueConstructCountForUser(
          userId,
          ConstructTypeEnum.vocab,
        );
        xpCount = analytics.totalXPForUser(userId);
        grammarCount = analytics.uniqueConstructCountForUser(
          userId,
          ConstructTypeEnum.morph,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => widget.controller.setShowDropdown(
          !widget.controller.showActivityDropdown,
        ),
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
