import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/subscription/models/power_ups_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PowerupsRepo {
  static const int _defaultPowerupsValue = 3;

  static PowerupsModel get _defaultPowerups => PowerupsModel(
        powerups: _defaultPowerupsValue,
        updated: DateTime.now(),
      );

  static bool get _isSubcribed =>
      MatrixState.pangeaController.subscriptionController.isSubscribed ?? true;

  static const String _powerupsKey = 'powerups';

  static final GetStorage _powerupsStorage = GetStorage('powerups_storage');

  static Future<void> initialize() async {
    await GetStorage.init('powerups_storage');
  }

  static Map<String, PowerupsModel> get _locallyCachedPowerups {
    final Map<String, dynamic> entry =
        _powerupsStorage.read(_powerupsKey) ?? {};

    final Map<String, PowerupsModel> powerupsMap = {};
    for (final entry in entry.entries) {
      powerupsMap[entry.key] = PowerupsModel.fromJson(entry.value);
    }

    return powerupsMap;
  }

  static Future<void> _set(
    String userID,
    int powerups, {
    DateTime? updated,
  }) async {
    final cachedPowerups =
        Map<String, PowerupsModel>.from(_locallyCachedPowerups);

    if (_isSubcribed) {
      if (cachedPowerups[userID] != null) await delete(userID);
      return;
    }

    final PowerupsModel currentValue =
        cachedPowerups[userID] ?? _defaultPowerups;

    final newValue = PowerupsModel(
      powerups: powerups,
      updated: updated ?? currentValue.updated,
    );

    cachedPowerups[userID] = newValue;

    final Map<String, dynamic> powerupsJson = {};
    for (final entry in cachedPowerups.entries) {
      powerupsJson[entry.key] = entry.value.toJson();
    }

    await _powerupsStorage.write(_powerupsKey, powerupsJson);
  }

  static Future<void> delete(String userID) async {
    final cachedPowerups = Map<String, PowerupsModel>.from(
      _locallyCachedPowerups,
    );
    cachedPowerups.remove(userID);
    await _powerupsStorage.write(_powerupsKey, cachedPowerups);
  }

  static int get(String userID) {
    final value = _locallyCachedPowerups[userID];
    if (value == null) {
      _reset(userID);
      return _defaultPowerupsValue;
    }

    if (value.updated.add(const Duration(days: 1)).isBefore(DateTime.now())) {
      _reset(userID);
      return _defaultPowerupsValue;
    }

    return _locallyCachedPowerups[userID]!.powerups;
  }

  static Future<void> usePowerup(String userID) async {
    if (_isSubcribed) return;

    final value = get(userID);
    if (value <= 0) {
      throw Exception('No power-ups left for user $userID');
    }
    await _set(userID, value - 1);
    MatrixState.pangeaController.subscriptionController.powerupsStream
        .add(null);
  }

  static Future<void> _reset(String userID) async {
    await _set(
      userID,
      _defaultPowerups.powerups,
      updated: DateTime.now(),
    );
  }
}
