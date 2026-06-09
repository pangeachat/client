import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/course_code_onboarding_step.dart';

class CourseCodeStepView extends StatefulWidget {
  final CourseCodeOnboardingStep step;
  final VoidCallback updateNavigationButton;
  final Object? error;

  const CourseCodeStepView({
    super.key,
    required this.step,
    required this.updateNavigationButton,
    required this.error,
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
    _codeController.text = _step.state.courseCode ?? "";
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
      widget.updateNavigationButton();
      _debounce?.cancel();
      _debounce = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        spacing: 12.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          BotFace(expression: BotExpression.idle, useRive: true, width: 140.0),
          Text(
            widget.error != null
                ? L10n.of(context).courseCodeStepErrorMessage
                : L10n.of(context).courseCodeStepTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: widget.error != null ? theme.colorScheme.error : null,
            ),
          ),
          TextField(
            controller: _codeController,
            decoration: InputDecoration(
              hintText: L10n.of(context).courseCodeStepHint,
              helperText: '', // reserves the error space permanently
              errorText: widget.error != null ? '' : null,
              suffixIcon: widget.error != null
                  ? Icon(Icons.error, color: theme.colorScheme.error)
                  : null,
            ),
            inputFormatters: [LengthLimitingTextInputFormatter(10)],
          ),
        ],
      ),
    );
  }
}
