import 'dart:collection';
import 'dart:math';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/features/join_codes/knock_with_code_extension.dart';
import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_mismatch_popup.dart';

class OnboardingNavigationController {
  late OnboardingStep _currentStep;

  OnboardingNavigationController({required OnboardingStep initialStep}) {
    _currentStep = initialStep;
  }

  int _currentStepIndex = 1;

  int get currentStepIndex => _currentStepIndex;

  final Queue<OnboardingStep> _prevSteps = Queue();

  OnboardingStep get step => _currentStep;

  bool get hasNextStep => _currentStep.maxRemainingSteps > 0;
  bool get hasPrevStep => _prevSteps.isNotEmpty;

  int get totalSteps => _currentStepIndex + _currentStep.maxRemainingSteps;

  double get progress => max(0.0, min(1.0, _currentStepIndex / totalSteps));

  Future<NavigationResult> forward() async {
    try {
      final nextStep = await _currentStep.execute();
      if (nextStep == null) {
        return ReachedEndNavigationResult();
      }

      _currentStepIndex++;
      _prevSteps.addLast(_currentStep);
      _currentStep = nextStep;
      return SuccessNavigationResult(nextStep);
    } catch (e, s) {
      // Join-with-code failures were already reported by the repo layer
      // (SpaceCodeController, with the attempted code attached); a second
      // event here double-reports the same failure, which the client error
      // contract forbids (repos-and-error-handling.instructions.md, #8693).
      final reportedByJoinFlow =
          e is PangeaHttpException ||
          e is BannedFromRoomException ||
          e is NotFoundException;
      final Map<String, dynamic> data = {'current_step': _currentStep};
      if (e is IdenticalLanguageException) {
        await ErrorHandler.logErrorOnce(
          key: IdenticalLanguageException.reportKey,
          e: e,
          s: s,
          data: data,
          level: SentryLevel.warning,
        );
      } else if (!reportedByJoinFlow) {
        ErrorHandler.logError(e: e, s: s, data: data);
      }
      return ErrorNavigationResult(e);
    }
  }

  NavigationResult skip() {
    try {
      final nextStep = _currentStep.skip();
      if (nextStep == null) {
        return ReachedEndNavigationResult();
      }

      _currentStepIndex++;
      _prevSteps.addLast(_currentStep);
      _currentStep = nextStep;
      return SuccessNavigationResult(nextStep);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'current_step': _currentStep});
      return ErrorNavigationResult(e);
    }
  }

  NavigationResult back() {
    if (_prevSteps.isEmpty) {
      return ReachedBeginningNavigationResult();
    }

    final prevStep = _prevSteps.removeLast();

    _currentStepIndex--;
    _currentStep = prevStep;
    return SuccessNavigationResult(prevStep);
  }
}
