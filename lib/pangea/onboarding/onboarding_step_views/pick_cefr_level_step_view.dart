import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/learning_settings/language_level_type_enum.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/pick_cefr_level_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';

class PickCefrLevelStepView extends StatefulWidget {
  final PickCefrLevelOnboardingStep step;
  final VoidCallback onUpdate;

  const PickCefrLevelStepView({
    super.key,
    required this.step,
    required this.onUpdate,
  });

  @override
  PickCefrLevelStepViewState createState() => PickCefrLevelStepViewState();
}

class PickCefrLevelStepViewState extends State<PickCefrLevelStepView> {
  late PickCefrLevelOnboardingStep _step;
  LanguageLevelTypeEnum? _selectedLevel;

  @override
  void initState() {
    super.initState();
    _step = widget.step;
    _selectedLevel = _step.level;
  }

  void _setLevel(LanguageLevelTypeEnum? level) {
    _selectedLevel = level;
    _step.selectCefrLevel(level);
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = switch (_step.type) {
      UserType.student => L10n.of(context).pickCefrLevelStudentStepTitle,
      UserType.teacher => L10n.of(context).pickCefrLevelTeacherStepTitle,
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
          child: ListView.separated(
            separatorBuilder: (context, i) => SizedBox(height: 4.0),
            itemCount: levels.length,
            itemBuilder: (context, i) {
              final level = levels[i];
              final selected = _selectedLevel == level;
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
      ],
    );
  }
}
