import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_settings/analytics_settings_model.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/widgets/matrix.dart';

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

extension AnalyticsSettingsClientExtension on Client {
  Future<void> blockLemma(String lemma) async {
    final l2 = MatrixState.pangeaController.languageController.userL2!;
    final analyticsRoom = await getMyAnalyticsRoom(l2);
    if (analyticsRoom == null) {
      throw Exception("Could not get or create analytics room");
    }

    final current = analyticsRoom.analyticsSettings;
    final blockedLemmas = current?.blockedLemmas ?? {};
    final updated = current?.copyWith(
      blockedLemmas: {
        ...blockedLemmas,
        lemma,
      },
    );

    await analyticsRoom.setAnalyticsSettings(updated!);
  }
}
