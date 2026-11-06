import 'dart:async';

import 'package:matrix/matrix.dart' hide Profile;

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/user/user_constants.dart';
import 'package:fluffychat/features/user/user_model.dart';
import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';
import 'package:fluffychat/routes/onboarding/onboarding_settings_model.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';

extension OnboardingClientExtension on Client {
  OnboardingSettingsModel get _onboardingSettingsModel {
    final entry = accountData[PangeaEventTypes.onboardingSettings];
    if (entry != null) {
      return OnboardingSettingsModel.fromJson(entry.content);
    }
    return OnboardingSettingsModel(showedTrialPage: false);
  }

  bool get showedTrialPage => _onboardingSettingsModel.showedTrialPage;

  /// This account's saved settings, read from this client's own account data
  /// rather than the process-wide profile cache, which belongs to whichever
  /// account is foregrounded.
  UserSettings? get savedUserSettings => Profile.fromAccountData(
    accountData[UserConstants.userProfile]?.content,
  )?.userSettings;

  /// The role this account chose in an earlier onboarding, so a restarted
  /// onboarding resumes on the same path.
  UserType? get selfIdentifiedRole => savedUserSettings?.selfIdentifiedRole;

  Map<String, Object?> get _progress =>
      accountData[PangeaEventTypes.onboardingProgress]?.content ?? const {};

  /// The account whose onboarding reached its end on this client in this
  /// session, whether or not the finished mark has saved yet.
  static final Expando<String> _finishedHere = Expando();

  /// Whether this account started an onboarding run and has not finished it,
  /// so it is sent back to onboarding. An account with neither mark predates
  /// the marks and counts as finished (onboarding.instructions.md § What
  /// onboarding reads and saves).
  bool get onboardingUnfinished =>
      _progress['started'] == true &&
      _progress['finished'] != true &&
      _finishedHere[this] != userID;

  /// Marks a run started, for an account with no marks and no L2. An account
  /// that saved its L2 before the marks existed finished onboarding then.
  Future<void> markOnboardingStarted() async {
    if (_progress.isNotEmpty || savedUserSettings?.targetLanguage != null) {
      return;
    }
    await setAccountData(userID!, PangeaEventTypes.onboardingProgress, {
      ..._progress,
      'started': true,
    });
  }

  /// Marks the run finished. The person is let into the app at once, before
  /// the write lands or even if it fails, so a failed save never keeps them in
  /// onboarding; an unsaved mark resumes it on the next app open.
  Future<void> markOnboardingFinished() async {
    _finishedHere[this] = userID;
    await setAccountData(userID!, PangeaEventTypes.onboardingProgress, {
      ..._progress,
      'finished': true,
    });
  }

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
