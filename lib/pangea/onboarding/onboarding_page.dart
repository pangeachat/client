import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_navigation_state.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_skip_buttons/onboarding_step_skip_button.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_views/onboarding_step_view.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/widgets/matrix.dart';

class Onboarding extends StatefulWidget {
  const Onboarding({super.key});

  @override
  OnboardingController createState() => OnboardingController();
}

class OnboardingController extends State<Onboarding> {
  late final OnboardingNavigationState _navState;

  late final ValueNotifier<OnboardingStep> _step;
  final ValueNotifier<bool> _loading = ValueNotifier(false);
  final ValueNotifier<Object?> _error = ValueNotifier(null);
  final ValueNotifier<bool> _enableNext = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    final initialStep = ProfileSetupOnboardingStep(
      client: Matrix.of(context).client,
    );
    _step = ValueNotifier(initialStep);
    _navState = OnboardingNavigationState(initialStep: initialStep);
    _updateEnableNext();
  }

  @override
  void dispose() {
    _step.dispose();
    _loading.dispose();
    _error.dispose();
    _enableNext.dispose();
    super.dispose();
  }

  void _updateEnableNext() => _enableNext.value = _step.value.enableGoForward;

  Future<void> _forward() async {
    _loading.value = true;
    _dispatchNavigationResult(await _navState.forward());
  }

  void _skip() => _dispatchNavigationResult(_navState.skip());

  void _back() => _dispatchNavigationResult(_navState.back());

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
        title: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Row(
            children: [
              ValueListenableBuilder(
                valueListenable: _step,
                builder: (context, step, _) => step.hasPrevStep
                    ? BackButton(onPressed: _back)
                    : const SizedBox(width: 40.0),
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: _step,
                  builder: (context, step, _) => AnimatedProgressBar(
                    height: 25.0,
                    widthPercent: step.stepIndex / step.totalSteps,
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
                      ValueListenableBuilder(
                        valueListenable: _enableNext,
                        builder: (context, enableNext, child) => ElevatedButton(
                          onPressed: enableNext ? _forward : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            foregroundColor:
                                theme.colorScheme.onPrimaryContainer,
                          ),
                          child: child,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ValueListenableBuilder(
                              valueListenable: _loading,
                              child: Text(
                                step.hasNextStep
                                    ? L10n.of(context).next
                                    : L10n.of(context).letsGo,
                              ),
                              builder: (context, loading, child) {
                                return loading
                                    ? const LinearProgressIndicator()
                                    : child!;
                              },
                            ),
                          ],
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
