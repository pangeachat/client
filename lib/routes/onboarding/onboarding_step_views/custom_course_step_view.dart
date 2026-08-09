import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/custom_course_onboarding_step.dart';

class CustomCourseStepView extends StatefulWidget {
  final CustomCourseOnboardingStep step;
  final bool loading;
  final bool hasNextStep;
  final VoidCallback forward;
  final VoidCallback skip;

  const CustomCourseStepView({
    super.key,
    required this.step,
    required this.loading,
    required this.hasNextStep,
    required this.forward,
    required this.skip,
  });

  @override
  CustomCourseStepViewState createState() => CustomCourseStepViewState();
}

class CustomCourseStepViewState extends State<CustomCourseStepView> {
  late final CustomCourseOnboardingStep _step;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _institutionController = TextEditingController();
  final TextEditingController _goalsController = TextEditingController();

  Timer? _nameDebounce;
  Timer? _institutionDebounce;
  Timer? _goalsDebounce;

  final ValueNotifier<bool> _enabledNotifier = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _step = widget.step;
    _enabledNotifier.value = _step.enableGoForward;

    _nameController.addListener(_setName);
    _institutionController.addListener(_setInstitution);
    _goalsController.addListener(_setGoals);
  }

  @override
  void dispose() {
    _nameController.removeListener(_setName);
    _institutionController.removeListener(_setInstitution);
    _goalsController.removeListener(_setGoals);
    _nameController.dispose();
    _institutionController.dispose();
    _goalsController.dispose();
    _nameDebounce?.cancel();
    _institutionDebounce?.cancel();
    _goalsDebounce?.cancel();
    super.dispose();
  }

  void _setName() {
    _nameDebounce?.cancel();
    _nameDebounce = Timer(Duration(milliseconds: 300), () {
      _step.setName(_nameController.text);
      _nameDebounce?.cancel();
      _nameDebounce = null;
      _enabledNotifier.value = _step.enableGoForward;
    });
  }

  void _setInstitution() {
    _institutionDebounce?.cancel();
    _institutionDebounce = Timer(Duration(milliseconds: 300), () {
      _step.setInstitution(_institutionController.text);
      _institutionDebounce?.cancel();
      _institutionDebounce = null;
      _enabledNotifier.value = _step.enableGoForward;
    });
  }

  void _setGoals() {
    _goalsDebounce?.cancel();
    _goalsDebounce = Timer(Duration(milliseconds: 300), () {
      _step.setGoals(_goalsController.text);
      _goalsDebounce?.cancel();
      _goalsDebounce = null;
      _enabledNotifier.value = _step.enableGoForward;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 32.0,
      children: [
        Expanded(
          child: Center(
            child: Semantics(
              label: L10n.of(context).customCourseStepTitle,
              container: true,
              child: SingleChildScrollView(
                child: Column(
                  spacing: 8.0,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        L10n.of(context).customCourseStepTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Semantics(
                      container: true,
                      child: TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: L10n.of(context).name,
                        ),
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(254),
                        ],
                      ),
                    ),
                    Semantics(
                      container: true,
                      child: TextField(
                        controller: _institutionController,
                        decoration: InputDecoration(
                          hintText: L10n.of(context).institution,
                        ),
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(254),
                        ],
                      ),
                    ),
                    Semantics(
                      container: true,
                      child: TextField(
                        controller: _goalsController,
                        decoration: InputDecoration(
                          hintText: L10n.of(context).courseGoals,
                        ),
                        minLines: 10,
                        maxLines: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Column(
          spacing: 12.0,
          children: [
            TextButton(
              onPressed: widget.skip,
              child: Text(L10n.of(context).skipForNow),
            ),
            ValueListenableBuilder(
              valueListenable: _enabledNotifier,
              builder: (context, enabled, _) => ElevatedButton(
                onPressed: enabled ? widget.forward : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: SizedBox(
                  height: 24,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: widget.loading
                          ? SizedBox(
                              key: const ValueKey('loading'),
                              width: double.infinity,
                              child: const LinearProgressIndicator(),
                            )
                          : Text(
                              widget.hasNextStep
                                  ? _step.nextStepText(L10n.of(context))
                                  : _step.lastStepText(L10n.of(context)),
                              key: const ValueKey('text'),
                              textAlign: TextAlign.center,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
