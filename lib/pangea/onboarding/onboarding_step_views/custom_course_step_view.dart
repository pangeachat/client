import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/custom_course_onboarding_step.dart';

class CustomCourseStepView extends StatefulWidget {
  final CustomCourseOnboardingStep step;
  const CustomCourseStepView({super.key, required this.step});

  @override
  CustomCourseStepViewState createState() => CustomCourseStepViewState();
}

class CustomCourseStepViewState extends State<CustomCourseStepView> {
  late final CustomCourseOnboardingStep _step;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _aboutController = TextEditingController();

  Timer? _nameDebounce;
  Timer? _aboutDebounce;

  @override
  void initState() {
    super.initState();
    _step = widget.step;
    _nameController.addListener(_setName);
    _aboutController.addListener(_setAbout);
  }

  @override
  void dispose() {
    _nameController.removeListener(_setName);
    _aboutController.removeListener(_setAbout);
    _nameController.dispose();
    _aboutController.dispose();
    _nameDebounce?.cancel();
    _aboutDebounce?.cancel();
    super.dispose();
  }

  void _setName() {
    _nameDebounce?.cancel();
    _nameDebounce = Timer(Duration(milliseconds: 300), () {
      _step.setName(_nameController.text);
      _nameDebounce?.cancel();
      _nameDebounce = null;
    });
  }

  void _setAbout() {
    _aboutDebounce?.cancel();
    _aboutDebounce = Timer(Duration(milliseconds: 300), () {
      _step.setAbout(_aboutController.text);
      _aboutDebounce?.cancel();
      _aboutDebounce = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
          controller: _aboutController,
          decoration: InputDecoration(
            hintText: L10n.of(context).aboutYourClass,
          ),
          minLines: 10,
          maxLines: 10,
        ),
      ],
    );
  }
}
