import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/features/join_codes/qr_code_scan.dart';
import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_forward_button.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_step_body.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/course_code_onboarding_step.dart';
import 'package:fluffychat/widgets/announcing_snackbar.dart';

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

  /// A scanned QR code that holds no course code. Shown as the step's
  /// not-found error until the learner types or scans again.
  Object? _scanError;

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
    if (_scanError != null) setState(() => _scanError = null);
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 300), () {
      _step.setCourseCode(_codeController.text);
      _debounce?.cancel();
      _debounce = null;
      if (mounted) setState(() {});
    });
  }

  /// A course code read from the camera joins at once, with no extra confirm;
  /// anything else shows the not-found error and the step stays put.
  Future<void> _scanQrCode() async {
    final result = await QrCodeScan.open(context);
    if (!mounted || result == null) return;
    final scanned = result.code;
    if (result.cameraDenied || scanned == null) {
      ScaffoldMessenger.of(context).showSnackBarAnnounced(
        SnackBar(content: Text(L10n.of(context).scanQrCodeCameraDenied)),
      );
      return;
    }
    final code = QrCodeScan.courseCode(scanned);
    if (code == null) {
      setState(() => _scanError = NotFoundException());
      return;
    }
    _codeController.text = code;
    _debounce?.cancel();
    _step.setCourseCode(code);
    widget.forward();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _scanError ?? widget.error;
    final title = error != null
        ? SpaceCodeController.joinErrorMessage(
            context,
            error,
            notFoundError: L10n.of(context).courseCodeStepErrorMessage,
          )
        : L10n.of(context).courseCodeStepTitle;
    return Column(
      spacing: 32.0,
      children: [
        Expanded(
          child: Center(
            child: OnboardingStepBody(
              label: title,
              scrollable: true,
              child: Column(
                spacing: 12.0,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: BotFace(
                      expression: BotExpression.idle,
                      useRive: true,
                      width: 140.0,
                    ),
                  ),
                  ExcludeSemantics(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: error != null ? theme.colorScheme.error : null,
                      ),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: _showCodeInput,
                    builder: (context, showInput, _) {
                      if (showInput) {
                        final field = Semantics(
                          container: true,
                          child: TextField(
                            controller: _codeController,
                            decoration: InputDecoration(
                              hintText: L10n.of(context).courseCodeStepHint,
                              helperText:
                                  '', // reserves the error space permanently
                              errorText: error != null ? '' : null,
                              suffixIcon: error != null
                                  ? Icon(
                                      Icons.error,
                                      color: theme.colorScheme.error,
                                    )
                                  : null,
                            ),
                          ),
                        );
                        if (!QrCodeScan.available) return field;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            field,
                            OutlinedButton.icon(
                              onPressed: widget.loading ? null : _scanQrCode,
                              icon: const Icon(Icons.qr_code_scanner_outlined),
                              label: Text(L10n.of(context).scanQrCode),
                            ),
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
        ValueListenableBuilder(
          valueListenable: _showCodeInput,
          builder: (context, showInput, _) {
            if (!showInput) return SizedBox(height: 60.0);
            return Column(
              children: [
                Padding(
                  padding: EdgeInsetsGeometry.only(bottom: 12.0),
                  child: TextButton(
                    onPressed: widget.skip,
                    child: Text(L10n.of(context).courseCodeStepSkip),
                  ),
                ),
                OnboardingForwardButton(
                  onPressed: _step.enableGoForward ? widget.forward : null,
                  loading: widget.loading,
                  label: widget.hasNextStep
                      ? _step.nextStepText(L10n.of(context))
                      : _step.lastStepText(L10n.of(context)),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
