import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';

class CourseCodeStepView extends StatefulWidget {
  final CourseCodeOnboardingStep step;

  final bool loading;
  final Object? error;
  final bool hasNextStep;
  final VoidCallback forward;
  final VoidCallback skip;

  const CourseCodeStepView({
    super.key,
    required this.step,
    required this.loading,
    required this.error,
    required this.hasNextStep,
    required this.forward,
    required this.skip,
  });

  @override
  CourseCodeStepViewState createState() => CourseCodeStepViewState();
}

class CourseCodeStepViewState extends State<CourseCodeStepView> {
  late final CourseCodeOnboardingStep _step;

  final TextEditingController _codeController = TextEditingController();

  Timer? _debounce;

  final ValueNotifier<bool> _showCodeInput = ValueNotifier(false);

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
    _showCodeInput.dispose();
    super.dispose();
  }

  void _setShowCodeInput() {
    if (mounted) _showCodeInput.value = true;
  }

  void _setCourseCode() {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 300), () {
      _step.setCourseCode(_codeController.text);
      _debounce?.cancel();
      _debounce = null;
      if (mounted) setState(() {});
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
            child: SingleChildScrollView(
              child: Column(
                spacing: 12.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  BotFace(
                    expression: BotExpression.idle,
                    useRive: true,
                    width: 140.0,
                  ),
                  Text(
                    widget.error != null
                        ? L10n.of(context).courseCodeStepErrorMessage
                        : L10n.of(context).courseCodeStepTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: widget.error != null
                          ? theme.colorScheme.error
                          : null,
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: _showCodeInput,
                    builder: (context, showInput, _) {
                      if (showInput) {
                        return TextField(
                          controller: _codeController,
                          decoration: InputDecoration(
                            hintText: L10n.of(context).courseCodeStepHint,
                            helperText:
                                '', // reserves the error space permanently
                            errorText: widget.error != null ? '' : null,
                            suffixIcon: widget.error != null
                                ? Icon(
                                    Icons.error,
                                    color: theme.colorScheme.error,
                                  )
                                : null,
                          ),
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(10),
                          ],
                        );
                      }

                      return Column(
                        spacing: 12.0,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: EdgeInsetsGeometry.symmetric(
                              horizontal: 16.0,
                            ),
                            child: ElevatedButton(
                              onPressed: widget.skip,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.surfaceContainer,
                                foregroundColor: theme.colorScheme.onSurface,
                              ),
                              child: Row(
                                spacing: 8.0,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [Text(L10n.of(context).no)],
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsetsGeometry.symmetric(
                              horizontal: 16.0,
                            ),
                            child: ElevatedButton(
                              onPressed: _setShowCodeInput,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.surfaceContainer,
                                foregroundColor: theme.colorScheme.onSurface,
                              ),
                              child: Row(
                                spacing: 8.0,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [Text(L10n.of(context).yes)],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        //     Column(
        Column(
          children: [
            ValueListenableBuilder(
              valueListenable: _showCodeInput,
              builder: (context, showInput, _) {
                if (!showInput) return SizedBox();
                return Padding(
                  padding: EdgeInsetsGeometry.only(bottom: 12.0),
                  child: TextButton(
                    onPressed: widget.skip,
                    child: Text(L10n.of(context).courseCodeStepSkip),
                  ),
                );
              },
            ),
            ElevatedButton(
              onPressed: _step.enableGoForward ? widget.forward : null,
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
          ],
        ),
      ],
    );
  }
}
