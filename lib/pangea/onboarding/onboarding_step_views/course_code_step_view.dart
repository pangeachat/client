import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/course_code_onboarding_step.dart';

class CourseCodeStepView extends StatefulWidget {
  final CourseCodeOnboardingStep step;
  final VoidCallback onUpdate;

  const CourseCodeStepView({
    super.key,
    required this.step,
    required this.onUpdate,
  });

  @override
  CourseCodeStepViewState createState() => CourseCodeStepViewState();
}

class CourseCodeStepViewState extends State<CourseCodeStepView> {
  late final CourseCodeOnboardingStep _step;

  final TextEditingController _codeController = TextEditingController();

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _step = widget.step;
    _codeController.addListener(_setCourseCode);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _codeController.removeListener(_setCourseCode);
    _codeController.dispose();
    super.dispose();
  }

  void _setCourseCode() {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 300), () {
      _step.setCourseCode(_codeController.text);
      widget.onUpdate();
      _debounce?.cancel();
      _debounce = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 12.0,
      mainAxisSize: MainAxisSize.min,
      children: [
        BotFace(expression: BotExpression.idle, useRive: true, width: 140.0),
        Text(
          L10n.of(context).courseCodeStepTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        TextField(
          controller: _codeController,
          decoration: InputDecoration(
            hintText: L10n.of(context).courseCodeStepHint,
          ),
        ),
      ],
    );
  }
}
