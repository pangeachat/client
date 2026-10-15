import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/onboarding/onboarding_settings_model.dart';

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
    // Wait for the course plan, not just the membership: a space's initial
    // state syncs event by event, so a just-claimed course can show the
    // user as joined before its course plan arrives (#9368).
    bool hasCourse() {
      final room = getRoomById(roomId);
      return room?.membership == Membership.join && room?.coursePlan != null;
    }

    if (!hasCourse()) {
      try {
        await onSync.stream
            .firstWhere((_) => hasCourse())
            .timeout(Duration(seconds: 10));
      } catch (e) {
        if (e is! TimeoutException) rethrow;
      }
    }

    final room = getRoomById(roomId);
    if (room?.coursePlan == null) {
      throw "Room not found or doesn't contain course";
    }

    return room!.coursePlan!.uuid;
  }
}
