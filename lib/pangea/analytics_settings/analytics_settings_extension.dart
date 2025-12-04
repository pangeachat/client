import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_settings/analytics_settings_model.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension AnalyticsSettingsRoomExtension on Room {
  AnalyticsSettingsModel? get analyticsSettings {
    final event = getState(PangeaEventTypes.analyticsSettings);
    if (event == null) return null;
    return AnalyticsSettingsModel.fromJson(event.content);
  }

  Future<void> setAnalyticsSettings(
    AnalyticsSettingsModel settings,
  ) async {
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.analyticsSettings,
      "",
      settings.toJson(),
    );
  }
}
