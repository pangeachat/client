import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_access/access_notice_model.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

extension AccessNoticeExtension on Client {
  AccessNoticeModel get accessNoticeSettings {
    final data = accountData[PangeaEventTypes.accessNoticeShown];
    if (data != null) {
      return AccessNoticeModel.fromJson(data.content);
    }
    return const AccessNoticeModel(noticesAccepted: {});
  }

  List<String> get pendingAccessNoticeCourseIds => accessNoticeSettings
      .noticesAccepted
      .entries
      .where((e) => e.value == false)
      .map((e) => e.key)
      .toList();

  bool acceptedAccessNotice(String courseId) =>
      accessNoticeSettings.noticesAccepted[courseId] == true;

  Future<void> setAccessNoticePending(String courseId) =>
      _setAcceptedAccessNotice(courseId, false);

  Future<void> setAccessNoticeAccepted(String courseId) =>
      _setAcceptedAccessNotice(courseId, true);

  Future<void> _setAcceptedAccessNotice(String courseId, bool value) async {
    final prevModel = accessNoticeSettings;
    final updatedAccessShown = Map<String, bool>.from(
      prevModel.noticesAccepted,
    );
    updatedAccessShown[courseId] = value;
    await _setAccessNoticeSettings(
      prevModel.copyWith(noticesAccepted: updatedAccessShown),
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
