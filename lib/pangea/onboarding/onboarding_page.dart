import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/pangea/onboarding/account_updater.dart';
import 'package:fluffychat/pangea/onboarding/avatar_provider.dart';
import 'package:fluffychat/pangea/onboarding/course_provider.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_navigation_controller.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_skip_button.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_views/onboarding_step_view.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_language_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
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
  final ValueNotifier<bool> _enableNext = ValueNotifier(false);
  final ValueNotifier<String?> _selectedTargetLangCode = ValueNotifier(null);

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
    _updateEnableNext();
  }

  @override
  void dispose() {
    _step.dispose();
    _loading.dispose();
    _error.dispose();
    _enableNext.dispose();
    _selectedTargetLangCode.dispose();
    super.dispose();
  }

  void _updateEnableNext() {
    _enableNext.value = _step.value.enableGoForward;
    _selectedTargetLangCode.value = _step.value.state.targetLanguage?.langCode;
  }

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
      _updateEnableNext();
      _loading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            child: Column(
              spacing: 32.0,
              children: [
                Expanded(
                  child: Center(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([_step, _error]),
                      builder: (context, _) => OnboardingStepView(
                        step: _step.value,
                        updateEnableNext: _updateEnableNext,
                        error: _error.value,
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: _step,
                  builder: (context, step, _) => Column(
                    spacing: 12.0,
                    children: [
                      if (step.enableSkip)
                        OnboardingStepSkipButton(step: step, onPressed: _skip),
                      ListenableBuilder(
                        listenable: Listenable.merge([_enableNext, _selectedTargetLangCode]),
                        builder: (context, child) => ElevatedButton(
                          onPressed: _enableNext.value ? _forward : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            foregroundColor:
                                theme.colorScheme.onPrimaryContainer,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: SizedBox(
                            height: 24,
                            child: Center(
                              child: ValueListenableBuilder(
                                valueListenable: _loading,
                                builder: (context, loading, _) =>
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      child: loading
                                          ? SizedBox(
                                              key: const ValueKey('loading'),
                                              width: double.infinity,
                                              child:
                                                  const LinearProgressIndicator(),
                                            )
                                          : Text(
                                              _navigation.hasNextStep
                                                  ? (_step.value is PickLanguageOnboardingStep &&
                                                            _step.value.state.targetLanguage != null &&
                                                            _enableNext.value)
                                                        ? L10n.of(context).continueWithLang(
                                                            _step.value.state.targetLanguage!.getDisplayName(context),
                                                          )
                                                        : L10n.of(context).next
                                                  : L10n.of(context).letsGo,
                                              key: const ValueKey('text'),
                                              textAlign: TextAlign.center,
                                            ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
