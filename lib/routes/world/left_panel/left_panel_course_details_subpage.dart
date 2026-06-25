import 'package:flutter/material.dart';

import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details.dart';
import 'package:fluffychat/routes/world/left_panel/left_panel_close_button.dart';

class LeftPanelCourseDetailsSubpage extends StatelessWidget {
  final PanelToken token;
  final Uri currentUri;
  final bool foldedOver;
  final bool isColumnMode;

  const LeftPanelCourseDetailsSubpage({
    super.key,
    required this.token,
    required this.currentUri,
    required this.foldedOver,
    required this.isColumnMode,
  });

  @override
  Widget build(BuildContext context) {
    final spaceId = activeSpaceIdFor(currentUri);
    if (spaceId == null) return const SizedBox.shrink();
    return ChatDetails(
      roomId: spaceId,
      activeTab: token.param,
      embeddedCloseButton: LeftPanelCloseButton(
        token: token,
        currentUri: currentUri,
        foldedOver: foldedOver,
        isColumnMode: isColumnMode,
      ),
    );
  }
}
