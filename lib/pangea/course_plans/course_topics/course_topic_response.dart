import 'package:fluffychat/pangea/course_plans/course_topics/course_topic_model.dart';
import 'package:fluffychat/pangea/payload_client/models/course_plan/cms_course_plan_topic.dart';
import 'package:fluffychat/pangea/payload_client/paginated_response.dart';

class CourseTopicResponse {
  final List<CourseTopicModel> topics;

  CourseTopicResponse({required this.topics});

  factory CourseTopicResponse.fromCmsResponse(
    PayloadPaginatedResponse<CmsCoursePlanTopic> response,
  ) {
    final topics = response.docs.map((topic) {
      return topic.toCourseTopicModel();
    }).toList();
    return CourseTopicResponse(topics: topics);
  }
}
