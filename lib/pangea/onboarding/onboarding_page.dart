import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_summary/animated_progress_bar.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_navigation_result.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_skip_buttons/onboarding_step_skip_button.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_step_state.dart';
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
  late final OnboardingStepState _state;

  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final initialStep = ProfileSetupOnboardingStep(
      client: Matrix.of(context).client,
    );
    _state = OnboardingStepState(initialStep: initialStep);
    _updateEnableNext();
  }

  OnboardingStep get _step => _state.step;

  void _updateEnableNext() {
    setState(() {});
  }

  Future<void> _forward() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final result = await _state.forward();
      if (result is ReachedEndNavigationResult) {
        context.go(_step.stepDestination);
        return;
      }
    } catch (e, s) {
      _error = e;
      ErrorHandler.logError(e: e, s: s, data: {});
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _skip() {
    final result = _state.skip();
    if (result is ReachedEndNavigationResult) {
      context.go(_step.stepDestination);
      return;
    }
    setState(() {});
  }

  void _back() {
    _state.back();
    setState(() {});
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
              _step.hasPrevStep
                  ? BackButton(onPressed: _step.enableGoBack ? _back : null)
                  : const SizedBox(width: 40.0),
              Expanded(
                child: AnimatedProgressBar(
                  height: 25.0,
                  widthPercent: _step.progress,
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
                    child: OnboardingStepView(
                      step: _step,
                      onUpdate: _updateEnableNext,
                      error: _error,
                    ),
                  ),
                ),
                Column(
                  spacing: 12.0,
                  children: [
                    if (_step.enableSkip)
                      OnboardingStepSkipButton(step: _step, onPressed: _skip),
                    ElevatedButton(
                      onPressed: _step.enableGoForward ? _forward : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _loading
                              ? Expanded(child: LinearProgressIndicator())
                              : Text(
                                  _step.hasNextStep
                                      ? L10n.of(context).next
                                      : L10n.of(context).letsGo,
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
