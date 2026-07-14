import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/routes/onboarding/account_updater.dart';
import 'package:fluffychat/routes/onboarding/avatar_provider.dart';
import 'package:fluffychat/routes/onboarding/course_provider.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_button_state.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_step_view.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/trial_info_provider.dart';
import 'package:fluffychat/widgets/animated_progress_bar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class Onboarding extends StatefulWidget {
  const Onboarding({super.key});

  @override
  OnboardingController createState() => OnboardingController();
}

class OnboardingController extends State<Onboarding> {
  late final OnboardingNavigationController _navigation;
  late final OnboardingStateController _state;

  late final ValueNotifier<OnboardingStep> _step;
  final ValueNotifier<bool> _loading = ValueNotifier(false);
  final ValueNotifier<Object?> _error = ValueNotifier(null);
  final ValueNotifier<OnboardingNavigationButtonState>
  _navigationButtonNotifier = ValueNotifier(
    OnboardingNavigationButtonState(enabled: false, target: null),
  );

  @override
  void initState() {
    super.initState();
    final client = Matrix.of(context).client;

    _state = OnboardingStateController(
      accountUpdater: UserAccountUpdater(),
      courseProvider: ClientCourseProvider(client: client),
      avatarProvider: RandomAvatarProvider(),
      trialInfoProvider: ClientTrialInfoProvider(
        client: client,
        inTrialWindow: MatrixState.pangeaController.userController
            .inTrialWindow(),
      ),
    );

    final initialStep = ProfileSetupOnboardingStep(
      client: client,
      state: _state,
      maxRemainingSteps: 5,
    );

    _step = ValueNotifier(initialStep);
    _navigation = OnboardingNavigationController(initialStep: initialStep);
    _updateNavigationButton();
  }

  @override
  void dispose() {
    _step.dispose();
    _loading.dispose();
    _error.dispose();
    _navigationButtonNotifier.dispose();
    super.dispose();
  }

  void _updateNavigationButton() =>
      _navigationButtonNotifier.value = OnboardingNavigationButtonState(
        enabled: _step.value.enableGoForward,
        target: _state.targetLanguage,
      );

  Future<void> _forward() async {
    GoogleAnalytics.completeTutorialStep(
      'onboarding',
      _navigation.currentStepIndex,
    );
    _loading.value = true;
    _dispatchNavigationResult(await _navigation.forward());
  }

  void _skip() => _dispatchNavigationResult(_navigation.skip());

  void _back() => _dispatchNavigationResult(_navigation.back());

  String labelByStepIndex(int i) {
    switch (i) {
      case 1:
        return L10n.of(context).editProfile;
      case 2:
        return L10n.of(context).useType;
      case 3:
        return L10n.of(context).joinWithClassCode;
      case 4:
        return L10n.of(context).languages;
      case 5:
        return L10n.of(context).level;
      case 6:
        return L10n.of(context).courseRequest;
      default:
        return L10n.of(context).onboarding;
    }
  }

  void _dispatchNavigationResult(NavigationResult result) {
    if (mounted) _error.value = null;

    switch (result) {
      case SuccessNavigationResult(step: final OnboardingStep step):
        _step.value = step;
      case ErrorNavigationResult(error: final Object error):
        _error.value = error;
      case ReachedBeginningNavigationResult():
      case ReachedEndNavigationResult():
        // world_v2: a joined course opens as a token-native `course` panel,
        // which needs the current workspace URI to build — the step only
        // exposes the space id ([joinedCourseSpaceId]); every other step
        // still returns a plain [stepDestination] path. See
        // routing.instructions.md.
        final spaceId = _step.value.joinedCourseSpaceId;
        context.go(
          spaceId != null
              ? WorkspaceNav.openCourseSection(
                  GoRouterState.of(context).uri,
                  spaceId,
                )
              : _step.value.stepDestination,
        );
    }

    if (mounted) {
      _updateNavigationButton();
      _loading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _step,
      builder: (context, step, _) {
        final content = ListenableBuilder(
          listenable: Listenable.merge([_error, _loading]),
          builder: (context, _) {
            return OnboardingStepView(
              step: step,
              updateNavigationButton: _updateNavigationButton,
              error: _error.value,
              loading: _loading.value,
              hasNextStep: _navigation.hasNextStep,
              forward: _forward,
              skip: _skip,
            );
          },
        );

        if (step.customView) {
          return content;
        }

        return Semantics(
          label: L10n.of(
            context,
          ).pageLabel(labelByStepIndex(_navigation.currentStepIndex)),
          child: Scaffold(
            appBar: AppBar(
              centerTitle: true,
              title: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Row(
                  children: [
                    _navigation.hasPrevStep
                        ? BackButton(onPressed: _back)
                        : const SizedBox(width: 40.0),
                    Expanded(
                      child: AnimatedProgressBar(
                        height: 25.0,
                        widthPercent: _navigation.progress,
                      ),
                    ),
                    const SizedBox(width: 40.0),
                  ],
                ),
              ),
              automaticallyImplyLeading: false,
            ),
            body: SafeArea(
              child: Center(
                child: Container(
                  width: 350.0,
                  padding: EdgeInsets.symmetric(vertical: 48.0),
                  child: content,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
