import 'package:flutter/material.dart';

import 'package:fluffychat/features/navigation/token_params/course_details_token.dart';
import 'package:fluffychat/features/tutorials/tutorial_target.dart';
import 'package:fluffychat/features/tutorials/tutorial_target_ids.dart';
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
    // Registered here rather than inside ChatDetails: this is the one place a
    // `course` token is rendered, so the id has a single claimant, and the rect
    // is the whole panel — header, close control and plan sections — which is
    // what the course tutorial's first step lights.
    return TutorialTarget(
      targetId: TutorialTargetIds.coursePanel,
      child: ChatDetails(
        roomId: spaceId,
        activeTab: param?.activeTab,
        expandedSection: param?.expanded ?? false,
        embeddedCloseButton: closeButton,
      ),
    );
  }
}
