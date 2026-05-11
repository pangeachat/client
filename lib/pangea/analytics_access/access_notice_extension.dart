import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_access/access_notice_model.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension AccessNoticeExtension on Client {
  bool sawAccessNotice(String courseId) =>
      _accessNoticeSettings.noticesShown[courseId] == true;

  AccessNoticeModel get _accessNoticeSettings {
    final data = accountData[PangeaEventTypes.accessNoticeShown];
    if (data != null) {
      return AccessNoticeModel.fromJson(data.content);
    }
    return const AccessNoticeModel(noticesShown: {});
  }

  Future<void> setSawAccessNotice(String courseId) async {
    final prevModel = _accessNoticeSettings;
    final updatedAccessShown = Map<String, bool>.from(prevModel.noticesShown);
    updatedAccessShown[courseId] = true;
    await _setAccessNoticeSettings(
      prevModel.copyWith(noticesShown: updatedAccessShown),
    );
  }

  Future<void> _setAccessNoticeSettings(AccessNoticeModel model) async {
    await setAccountData(
      userID!,
      PangeaEventTypes.accessNoticeShown,
      model.toJson(),
    );
  }
}
