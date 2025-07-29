import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_planner/activity_participant_indicator.dart';
import 'package:fluffychat/pangea/activity_planner/activity_room_extension.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class JoinActivityWidget extends StatefulWidget {
  final Room room;

  const JoinActivityWidget({
    super.key,
    required this.room,
  });

  @override
  JoinActivityWidgetState createState() => JoinActivityWidgetState();
}

class JoinActivityWidgetState extends State<JoinActivityWidget> {
  int? _selectedRole;

  void _selectRole(int role) {
    if (_selectedRole == role) return;
    setState(() => _selectedRole = role);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final roles = widget.room.remainingRoles;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        child: AnimatedSize(
          duration: FluffyThemes.animationDuration,
          child: widget.room.activityPlan != null &&
                  !widget.room.hasJoinedActivity
              ? Padding(
                  padding: EdgeInsets.only(
                    bottom: FluffyThemes.isColumnMode(context) ? 32.0 : 16.0,
                    left: 16.0,
                    right: 16.0,
                  ),
                  child: Column(
                    spacing: 16.0,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (roles > 0)
                        Wrap(
                          spacing: 16.0,
                          runSpacing: 16.0,
                          children: List.generate(roles, (index) {
                            return ActivityParticipantIndicator(
                              selected: _selectedRole == index,
                              onTap: () => _selectRole(index),
                            );
                          }),
                        ),
                      Text(
                        roles > 0
                            ? L10n.of(context).unjoinedActivityMessage
                            : L10n.of(context).fullActivityMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isColumnMode ? 18.0 : 14.0,
                        ),
                      ),
                      if (roles > 0)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16.0),
                            foregroundColor:
                                theme.colorScheme.onPrimaryContainer,
                            backgroundColor: theme.colorScheme.primaryContainer,
                          ),
                          onPressed: _selectedRole != null
                              ? () {
                                  showFutureLoadingDialog(
                                    context: context,
                                    future: () => widget.room.setActivityRole(
                                      widget.room.client.userID!,
                                    ),
                                  );
                                }
                              : null,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(L10n.of(context).confirmRole),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
