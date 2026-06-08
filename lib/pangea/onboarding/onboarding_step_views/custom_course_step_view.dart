import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/custom_course_onboarding_step.dart';

class CustomCourseStepView extends StatefulWidget {
  final CustomCourseOnboardingStep step;
  final VoidCallback updateNavigationButton;
  const CustomCourseStepView({
    super.key,
    required this.step,
    required this.updateNavigationButton,
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

  @override
  void initState() {
    super.initState();
    _step = widget.step;

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
      widget.updateNavigationButton();
    });
  }

  void _setInstitution() {
    _institutionDebounce?.cancel();
    _institutionDebounce = Timer(Duration(milliseconds: 300), () {
      _step.setInstitution(_institutionController.text);
      _institutionDebounce?.cancel();
      _institutionDebounce = null;
      widget.updateNavigationButton();
    });
  }

  void _setGoals() {
    _goalsDebounce?.cancel();
    _goalsDebounce = Timer(Duration(milliseconds: 300), () {
      _step.setGoals(_goalsController.text);
      _goalsDebounce?.cancel();
      _goalsDebounce = null;
      widget.updateNavigationButton();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        spacing: 8.0,
        children: [
          Text(
            L10n.of(context).customCourseStepTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(hintText: L10n.of(context).name),
          ),
          TextField(
            controller: _institutionController,
            decoration: InputDecoration(hintText: L10n.of(context).institution),
          ),
          TextField(
            controller: _goalsController,
            decoration: InputDecoration(hintText: L10n.of(context).courseGoals),
            minLines: 10,
            maxLines: 10,
          ),
        ],
      ),
    );
  }
}
