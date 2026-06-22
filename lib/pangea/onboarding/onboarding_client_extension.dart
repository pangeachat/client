import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_settings_model.dart';

extension OnboardingClientExtension on Client {
  OnboardingSettingsModel get _onboardingSettingsModel {
    final entry = accountData[PangeaEventTypes.onboardingSettings];
    if (entry != null) {
      return OnboardingSettingsModel.fromJson(entry.content);
    }
    return OnboardingSettingsModel(showedTrialPage: false);
  }

  bool get showedTrialPage => _onboardingSettingsModel.showedTrialPage;

  Future<void> _setOnboardingSettings(OnboardingSettingsModel update) async {
    await setAccountData(
      userID!,
      PangeaEventTypes.onboardingSettings,
      update.toJson(),
    );
  }

  Future<void> setShowedTrialPage() => _setOnboardingSettings(
    _onboardingSettingsModel.copyWith(showedTrialPage: true),
  );

  Future<String> getCourseIdByRoomId(String roomId) async {
    Room? room = getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      try {
        await waitForRoomInSync(roomId).timeout(Duration(seconds: 10));
      } catch (e) {
        if (e is! TimeoutException) rethrow;
      }
    }

    room = getRoomById(roomId);
    if (room?.coursePlan == null) {
      throw "Room not found or doesn't contain course";
    }

    return room!.coursePlan!.uuid;
  }
}
