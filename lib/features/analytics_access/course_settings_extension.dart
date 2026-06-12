import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/course_settings_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

extension CourseSettingsExtension on Room {
  bool get requireAnalyticsAccess => _courseSettings.requireAnalyticsAccess;

  CourseSettingsModel get _courseSettings {
    final event = getState(PangeaEventTypes.courseSettings);
    if (event != null) {
      return CourseSettingsModel.fromJson(event.content);
    }
    return CourseSettingsModel();
  }

  Future<void> toggleRequireAnalyticsAccess() async {
    final current = _courseSettings;
    await _setCourseSettings(
      current.copyWith(requireAnalyticsAccess: !current.requireAnalyticsAccess),
    );
  }

  Future<void> _setCourseSettings(CourseSettingsModel model) async {
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.courseSettings,
      '',
      model.toJson(),
    );
  }
}
