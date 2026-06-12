import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_model.dart';
import 'package:fluffychat/pangea/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/routes/chat/chat_details/pin_clipper.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

class CourseTopicList extends StatelessWidget {
  final CoursePlanModel course;

  const CourseTopicList({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    const double titleFontSize = 16.0;
    const double descFontSize = 12.0;
    const double smallIconSize = 12.0;

    final theme = Theme.of(context);

    if (!course.topicListComplete) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return Column(
      spacing: 8,
      children: [
        ...course.topicIds
            .map((id) => course.loadedTopics[id])
            .whereType<CourseTopicModel>()
            .map(
              (topic) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  spacing: 8.0,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipPath(
                      clipper: PinClipper(),
                      child: ImageByUrl(
                        imageUrl: topic.imageUrl,
                        width: 45.0,
                        replacement: Container(
                          width: 45.0,
                          height: 45.0,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: Column(
                        spacing: 4.0,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topic.title,
                            style: const TextStyle(fontSize: titleFontSize),
                          ),
                          Padding(
                            padding: const EdgeInsetsGeometry.symmetric(
                              vertical: 2.0,
                            ),
                            child: Wrap(
                              spacing: 8.0,
                              runSpacing: 4.0,
                              children: [
                                if (topic.location != null)
                                  CourseInfoChip(
                                    icon: Icons.location_on,
                                    text: topic.location!,
                                    fontSize: descFontSize,
                                    iconSize: smallIconSize,
                                  ),
                                CourseInfoChip(
                                  icon: Icons.event_note,
                                  text:
                                      "${(topic.activityIds).length} ${L10n.of(context).activities}",
                                  fontSize: descFontSize,
                                  iconSize: smallIconSize,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
