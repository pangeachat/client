import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
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
    _loading.value = true;
    _dispatchNavigationResult(await _navigation.forward());
  }

  void _skip() => _dispatchNavigationResult(_navigation.skip());

  void _back() => _dispatchNavigationResult(_navigation.back());

  void _dispatchNavigationResult(NavigationResult result) {
    if (mounted) _error.value = null;

    switch (result) {
      case SuccessNavigationResult(step: final OnboardingStep step):
        _step.value = step;
      case ErrorNavigationResult(error: final Object error):
        _error.value = error;
      case ReachedBeginningNavigationResult():
      case ReachedEndNavigationResult():
        context.go(_step.value.stepDestination);
    }

    if (mounted) {
      _updateNavigationButton();
      _loading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Row(
            children: [
              ValueListenableBuilder(
                valueListenable: _step,
                builder: (context, step, _) => _navigation.hasPrevStep
                    ? BackButton(onPressed: _back)
                    : const SizedBox(width: 40.0),
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: _step,
                  builder: (context, step, _) => AnimatedProgressBar(
                    height: 25.0,
                    widthPercent: _navigation.progress,
                  ),
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
            child: ListenableBuilder(
              listenable: Listenable.merge([_step, _error, _loading]),
              builder: (context, _) {
                return OnboardingStepView(
                  step: _step.value,
                  updateNavigationButton: _updateNavigationButton,
                  error: _error.value,
                  loading: _loading.value,
                  hasNextStep: _navigation.hasNextStep,
                  forward: _forward,
                  skip: _skip,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
