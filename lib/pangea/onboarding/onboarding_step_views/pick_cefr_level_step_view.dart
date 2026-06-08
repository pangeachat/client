import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PickCefrLevelStepView extends StatefulWidget {
  final PickCefrLevelOnboardingStep step;
  final VoidCallback updateNavigationButton;

  const PickCefrLevelStepView({
    super.key,
    required this.step,
    required this.updateNavigationButton,
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
    _selectedLevel.value = level;
    _step.selectCefrLevel(level);
    widget.updateNavigationButton();
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
                  child: Row(children: [Text(level.title(context))]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
