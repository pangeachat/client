import 'package:get_storage/get_storage.dart';

import 'package:fluffychat/pangea/common/constants/local.key.dart';

class SpaceCodeRepo {
  static final GetStorage _spaceStorage = GetStorage('class_storage');

  static String? get spaceCode =>
      _spaceStorage.read(PLocalKey.cachedSpaceCodeToJoin);

  static String? get recentCode =>
      _spaceStorage.read(PLocalKey.justInputtedCode);

  static Future<void> setSpaceCode(String code) async {
    if (code.isEmpty) return;
    await _spaceStorage.write(PLocalKey.cachedSpaceCodeToJoin, code);
  }

  static Future<void> setRecentCode(String code) async {
    await _spaceStorage.write(PLocalKey.justInputtedCode, code);
  }

  static Future<void> clearSpaceCode() async {
    await _spaceStorage.remove(PLocalKey.cachedSpaceCodeToJoin);
  }

  static Future<void> clearRecentCode() async {
    await _spaceStorage.remove(PLocalKey.justInputtedCode);
  }
}
