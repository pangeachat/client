import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/routes/onboarding/user_type_enum.dart';
import 'package:fluffychat/routes/settings/settings_learning/language_level_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PickCefrLevelStepView extends StatefulWidget {
  final PickCefrLevelOnboardingStep step;
  final bool loading;
  final bool hasNextStep;
  final VoidCallback forward;

  const PickCefrLevelStepView({
    super.key,
    required this.step,
    required this.loading,
    required this.hasNextStep,
    required this.forward,
  });

  @override
  PickCefrLevelStepViewState createState() => PickCefrLevelStepViewState();
}

class PickCefrLevelStepViewState extends State<PickCefrLevelStepView> {
  late PickCefrLevelOnboardingStep _step;
  final ValueNotifier<LanguageLevelTypeEnum?> _selectedLevel = ValueNotifier(
    null,
  );

  @override
  void initState() {
    super.initState();
    _step = widget.step;
    final userLevel = MatrixState.pangeaController.userController.userCefrLevel;
    if (_step.state.languageLevel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setLevel(userLevel));
    }
  }

  @override
  void dispose() {
    _selectedLevel.dispose();
    super.dispose();
  }

  void _setLevel(LanguageLevelTypeEnum? level) {
    _step.selectCefrLevel(level);
    _selectedLevel.value = level;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = _step.state.userType;

    final title = switch (type) {
      UserType.student => L10n.of(context).pickCefrLevelStudentStepTitle,
      UserType.teacher => L10n.of(context).pickCefrLevelTeacherStepTitle,
      null => L10n.of(context).pickCefrLevelStudentStepTitle,
    };

    final levels = LanguageLevelTypeEnum.values;
    return Column(
      spacing: 32.0,
      children: [
        Expanded(
          child: Center(
            child: Column(
              spacing: 12.0,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _selectedLevel,
                    builder: (context, selectedLevel, _) => ListView.separated(
                      separatorBuilder: (context, i) => SizedBox(height: 4.0),
                      itemCount: levels.length,
                      itemBuilder: (context, i) {
                        final level = levels[i];
                        final selected = selectedLevel == level;
                        return ElevatedButton(
                          onPressed: () => _setLevel(selected ? null : level),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: selected
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainer,
                            foregroundColor: selected
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Column(
                            spacing: 8.0,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    level.title(context),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              Text(
                                level.description(context),
                                style: theme.textTheme.labelLarge,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _selectedLevel,
          builder: (context, _, _) => ElevatedButton(
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
        ),
      ],
    );
  }
}
