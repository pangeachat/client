import 'package:flutter/material.dart';

import 'package:fluffychat/features/navigation/token_params/course_details_token.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details.dart';

class LeftPanelCourseDetailsSubpage extends StatelessWidget {
  final CourseDetailsTokenParam? param;
  final String? spaceId;
  final Widget closeButton;

  const LeftPanelCourseDetailsSubpage({
    super.key,
    required this.param,
    required this.spaceId,
    required this.closeButton,
  });

  @override
  Widget build(BuildContext context) {
    final spaceId = this.spaceId;
    if (spaceId == null) return const SizedBox.shrink();
    return ChatDetails(
      roomId: spaceId,
      activeTab: param?.activeTab,
      embeddedCloseButton: closeButton,
    );
  }
}
