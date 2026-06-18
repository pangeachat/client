import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_settings/analytics_settings_model.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension AnalyticsSettingsRoomExtension on Room {
  AnalyticsSettingsModel get _analyticsSettings {
    final event = getState(PangeaEventTypes.analyticsSettings);
    if (event == null) {
      return const AnalyticsSettingsModel(blockedConstructs: {});
    }

    try {
      return AnalyticsSettingsModel.fromJson(event.content);
    } catch (_) {
      return AnalyticsSettingsModel(blockedConstructs: {});
    }
  }

  Map<ConstructIdentifier, BlockedConstruct> get blockedConstructs =>
      _analyticsSettings.blockedConstructs;

  Future<void> _setAnalyticsSettings(AnalyticsSettingsModel settings) async {
    await client.setRoomStateWithKey(
      id,
      PangeaEventTypes.analyticsSettings,
      "",
      settings.toJson(),
    );
  }

  Future<void> addBlockedConstructs(
    Map<ConstructIdentifier, BlockedConstruct> blocked,
  ) async {
    final current = blockedConstructs;
    final updated = {...current, ...blocked};
    if (current.length == updated.length) return;
    await _setAnalyticsSettings(
      _analyticsSettings.copyWith(blockedConstructs: updated),
    );
  }
}
