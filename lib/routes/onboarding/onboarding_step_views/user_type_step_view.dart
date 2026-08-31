import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_forward_button.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/user_type_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';

class UserTypeStepView extends StatefulWidget {
  final UserTypeOnboardingStep step;
  final bool loading;
  final bool hasNextStep;
  final VoidCallback forward;

  const UserTypeStepView({
    super.key,
    required this.step,
    required this.loading,
    required this.hasNextStep,
    required this.forward,
  });

  @override
  UserTypeStepViewState createState() => UserTypeStepViewState();
}

class UserTypeStepViewState extends State<UserTypeStepView> {
  late final UserTypeOnboardingStep _step;

  final ValueNotifier<UserType?> _selectedType = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _step = widget.step;
    _selectedType.value = _step.state.userType;
  }

  @override
  void dispose() {
    _selectedType.dispose();
    super.dispose();
  }

  void _setSelectedType(UserType type) {
    _step.setUserType(type);
    _selectedType.value = type;
    SemanticsService.sendAnnouncement(
      View.of(context),
      type.selectedMessage(L10n.of(context)),
      Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 32.0,
      children: [
        Expanded(
          child: Center(
            child: Column(
              spacing: 12.0,
              mainAxisSize: MainAxisSize.min,
              children: [
                BotFace(
                  expression: BotExpression.idle,
                  useRive: true,
                  width: 140.0,
                ),
                Semantics(
                  container: true,
                  child: Text(
                    L10n.of(context).userTypeTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: _selectedType,
                  builder: (context, type, _) => Column(
                    spacing: 12.0,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: EdgeInsetsGeometry.symmetric(horizontal: 16.0),
                        child: Opacity(
                          opacity: type != null && type != UserType.teacher
                              ? 0.5
                              : 1.0,
                          child: MergeSemantics(
                            child: Semantics(
                              selected: type == UserType.teacher,
                              child: ElevatedButton(
                                onPressed: () =>
                                    _setSelectedType(UserType.teacher),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: type == UserType.teacher
                                      ? theme.colorScheme.primaryContainer
                                      : theme.colorScheme.surfaceContainer,
                                  foregroundColor: type == UserType.teacher
                                      ? theme.colorScheme.onPrimaryContainer
                                      : theme.colorScheme.onSurface,
                                ),
                                child: Row(
                                  spacing: 8.0,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.school_outlined, size: 24.0),
                                    Text(L10n.of(context).teach),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsetsGeometry.symmetric(horizontal: 16.0),
                        child: Opacity(
                          opacity: type != null && type != UserType.student
                              ? 0.5
                              : 1.0,
                          child: MergeSemantics(
                            child: Semantics(
                              selected: type == UserType.student,
                              child: ElevatedButton(
                                onPressed: () =>
                                    _setSelectedType(UserType.student),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: type == UserType.student
                                      ? theme.colorScheme.primaryContainer
                                      : theme.colorScheme.surfaceContainer,
                                  foregroundColor: type == UserType.student
                                      ? theme.colorScheme.onPrimaryContainer
                                      : theme.colorScheme.onSurface,
                                ),
                                child: Row(
                                  spacing: 8.0,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Symbols.dictionary, size: 24.0),
                                    Text(L10n.of(context).learn),
                                  ],
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
        ValueListenableBuilder(
          valueListenable: _selectedType,
          builder: (context, _, _) => OnboardingForwardButton(
            onPressed: _step.enableGoForward ? widget.forward : null,
            loading: widget.loading,
            label: widget.hasNextStep
                ? _step.nextStepText(L10n.of(context))
                : _step.lastStepText(L10n.of(context)),
          ),
        ),
      ],
    );
  }
}
