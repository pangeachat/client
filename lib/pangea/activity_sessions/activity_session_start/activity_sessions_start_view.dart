import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_participant_list.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_session_start_page.dart';
import 'package:fluffychat/pangea/common/widgets/share_room_button.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';

class ActivitySessionStartView extends StatelessWidget {
  final ActivitySessionStartController controller;
  const ActivitySessionStartView(
    this.controller, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 52.0,
        title: Text(controller.displayname),
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Center(
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: SizedBox(
              width: 40.0,
              height: 40.0,
              child: Center(
                child: ShareRoomButton(room: controller.room),
              ),
            ),
          ),
        ],
      ),
      body: MaxWidthBody(
        showBorder: false,
        withScrolling: false,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                spacing: 12.0,
                children: [
                  ActivityParticipantList(room: controller.room),
                ],
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: theme.dividerColor)),
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  spacing: 16.0,
                  children: [
                    Text(
                      controller.descriptionText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        padding: const EdgeInsets.all(8.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20.0),
                        ),
                      ),
                      onPressed: () {},
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(controller.buttonText),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
