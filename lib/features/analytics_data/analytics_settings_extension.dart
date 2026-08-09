import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics_data/analytics_settings_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

extension AnalyticsSettingsRoomExtension on Room {
  AnalyticsSettingsModel get analyticsSettings {
    final event = getState(PangeaEventTypes.analyticsSettings);
    if (event == null) {
      return const AnalyticsSettingsModel(blockedConstructs: {});
    }
    return AnalyticsSettingsModel.fromJson(event.content);
  }

  Set<ConstructIdentifier> get blockedConstructs =>
      analyticsSettings.blockedConstructs;

  Future<void> setAnalyticsSettings(AnalyticsSettingsModel settings) async {
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.analyticsSettings,
      "",
      settings.toJson(),
    );
  }
}
