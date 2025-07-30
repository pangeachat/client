import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_planner/activity_participant_indicator.dart';
import 'package:fluffychat/pangea/activity_planner/activity_role_model.dart';
import 'package:fluffychat/pangea/activity_planner/activity_room_extension.dart';
import 'package:fluffychat/pangea/common/widgets/pressable_button.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/mxc_image.dart';

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
  ActivityRoleModel? _highlightedRole;

  @override
  void initState() {
    super.initState();
    _setDefaultHighlightedRole();
  }

  @override
  void didUpdateWidget(JoinActivityWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _setDefaultHighlightedRole();
  }

  void _setDefaultHighlightedRole() {
    if (_hightlightedRoleIndex >= 0) return;

    final roles = widget.room.activityRoles;
    _highlightedRole = roles.firstWhereOrNull(
      (r) => r.userId == widget.room.client.userID,
    );

    if (_highlightedRole == null && roles.isNotEmpty) {
      _highlightedRole = roles.first;
    }

    if (mounted) setState(() {});
  }

  int get _hightlightedRoleIndex {
    if (_highlightedRole == null) {
      return -1; // No highlighted role
    }
    return widget.room.activityRoles.indexOf(_highlightedRole!);
  }

  void _selectRole(int role) {
    if (_selectedRole == role) return;
    if (mounted) setState(() => _selectedRole = role);
  }

  void _highlightRole(ActivityRoleModel role) {
    if (mounted) setState(() => _highlightedRole = role);
  }

  bool get _canMoveLeft =>
      _hightlightedRoleIndex > 0 && _highlightedRole != null;

  bool get _canMoveRight =>
      _hightlightedRoleIndex < widget.room.activityRoles.length - 1 &&
      _highlightedRole != null;

  void _moveLeft() {
    if (_hightlightedRoleIndex > 0) {
      _highlightRole(widget.room.activityRoles[_hightlightedRoleIndex - 1]);
    }
  }

  void _moveRight() {
    if (_hightlightedRoleIndex < widget.room.activityRoles.length - 1) {
      _highlightRole(widget.room.activityRoles[_hightlightedRoleIndex + 1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final unassignedRoles = widget.room.remainingRoles;
    final allRoles = widget.room.activityRoles;

    if (widget.room.activityPlan == null) {
      return const SizedBox.shrink();
    }

    final imageURL = widget.room.activityPlan!.imageURL;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        child: AnimatedSize(
          duration: FluffyThemes.animationDuration,
          child: !widget.room.hasJoinedActivity ||
                  widget.room.activityIsFinished
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
                    children: widget.room.activityIsFinished
                        ? [
                            if (imageURL != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(100),
                                child: imageURL.startsWith("mxc")
                                    ? MxcImage(
                                        uri: Uri.parse(imageURL),
                                        width: 200.0,
                                        height: 200.0,
                                        cacheKey: widget
                                            .room.activityPlan!.bookmarkId,
                                        fit: BoxFit.cover,
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: imageURL,
                                        fit: BoxFit.cover,
                                        width: 200.0,
                                        height: 200.0,
                                        placeholder: (
                                          context,
                                          url,
                                        ) =>
                                            const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                        errorWidget: (
                                          context,
                                          url,
                                          error,
                                        ) =>
                                            const SizedBox(),
                                      ),
                              ),
                            const Text(
                              "This is the group Activity Summary Placeholder text.\nQuis varius quam quisque id diam. Aliquam sem et tortor consequat id porta nibh venenatis cras. Duis ut diam quam nulla. In metus vulputate eu scelerisque. Id aliquet lectus proin nibh nisl condimentum. ",
                              textAlign: TextAlign.center,
                            ),
                            if (_highlightedRole != null)
                              ActivityResultsCarousel(
                                selectedRole: _highlightedRole!,
                                moveLeft: _canMoveLeft ? _moveLeft : null,
                                moveRight: _canMoveRight ? _moveRight : null,
                                user: widget.room
                                    .getParticipants()
                                    .firstWhereOrNull(
                                      (u) => u.id == _highlightedRole!.userId,
                                    ),
                              ),
                            Wrap(
                              spacing: 16.0,
                              runSpacing: 16.0,
                              children: allRoles
                                  .map(
                                    (role) => Opacity(
                                      opacity:
                                          _highlightedRole == role ? 1.0 : 0.5,
                                      child: ActivityParticipantIndicator(
                                        onTap: () => _highlightRole(role),
                                        role: role,
                                        displayname: role.userId.localpart,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ]
                        : [
                            if (unassignedRoles > 0)
                              Wrap(
                                spacing: 16.0,
                                runSpacing: 16.0,
                                children:
                                    List.generate(unassignedRoles, (index) {
                                  return ActivityParticipantIndicator(
                                    selected: _selectedRole == index,
                                    onTap: () => _selectRole(index),
                                  );
                                }),
                              ),
                            Text(
                              unassignedRoles > 0
                                  ? L10n.of(context).unjoinedActivityMessage
                                  : L10n.of(context).fullActivityMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isColumnMode ? 18.0 : 14.0,
                              ),
                            ),
                            if (unassignedRoles > 0)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.all(16.0),
                                  foregroundColor:
                                      theme.colorScheme.onPrimaryContainer,
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                ),
                                onPressed: _selectedRole != null
                                    ? () {
                                        showFutureLoadingDialog(
                                          context: context,
                                          future: () =>
                                              widget.room.setActivityRole(
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

class ActivityResultsCarousel extends StatelessWidget {
  final ActivityRoleModel selectedRole;
  final User? user;

  final VoidCallback? moveLeft;
  final VoidCallback? moveRight;

  const ActivityResultsCarousel({
    super.key,
    required this.selectedRole,
    required this.moveLeft,
    required this.moveRight,
    this.user,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: moveLeft,
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: PressableButton(
            onPressed: () {},
            borderRadius: BorderRadius.circular(24.0),
            color: theme.brightness == Brightness.dark
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            colorFactor: theme.brightness == Brightness.dark ? 0.6 : 0.2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24.0),
              ),
              height: 300.0,
              width: 250.0,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(24.0),
                ),
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Avatar(
                        size: 64.0,
                        mxContent: user?.avatarUrl,
                        name: user?.calcDisplayname() ?? selectedRole.userId,
                        userId: selectedRole.userId,
                      ),
                    ),
                    Text(
                      selectedRole.role != null
                          ? "${selectedRole.role!} | ${selectedRole.userId.localpart}"
                          : "${selectedRole.userId.localpart}",
                    ),
                    const SizedBox(height: 10.0),
                    const Text(
                      "Personal summary of this user in text form.\n\nLorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ullamcorper a lacus vestibulum sed. ",
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_forward_ios),
          onPressed: moveRight,
        ),
      ],
    );
  }
}
