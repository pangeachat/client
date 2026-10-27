import 'package:flutter/material.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/widgets/avatar.dart';

/// The course an onboarding page names: the joined course, or the central
/// course a learner is offered.
class OnboardingCourseCard extends StatelessWidget {
  final Uri? avatar;
  final String name;
  final CoursePlanModel? plan;
  final String? courseRoomId;

  const OnboardingCourseCard({
    super.key,
    required this.avatar,
    required this.name,
    required this.plan,
    required this.courseRoomId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = this.plan;
    return Padding(
      padding: const EdgeInsetsGeometry.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(10.0),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.primaryContainer,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Column(
          spacing: 10.0,
          children: [
            SizedBox(
              height: 120.0,
              child: Row(
                spacing: 10.0,
                children: [
                  Avatar(
                    mxContent: avatar,
                    name: name,
                    borderRadius: BorderRadius.circular(10),
                    size: 120.0,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        if (plan != null)
                          CourseInfoChips(
                            plan.uuid,
                            courseRoomId: courseRoomId,
                            fontSize: 14,
                            iconSize: 12,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (plan != null)
              Text(
                plan.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
