import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_step_views/onboarding_forward_button.dart';
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
    // Seed the highlight from the persisted selection (or the profile default)
    // so it always reflects state.languageLevel: on re-entry the local notifier
    // is a fresh null, and without this the page showed nothing selected while
    // Next stayed enabled off the still-set state (#7583).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _setLevel(_step.state.languageLevel ?? userLevel, announce: false),
    );
  }

  @override
  void dispose() {
    _selectedLevel.dispose();
    super.dispose();
  }

  /// [announce] is false only for the entry seed above — a screen reader
  /// should hear a selection the user made, not the page restoring state.
  void _setLevel(LanguageLevelTypeEnum? level, {bool announce = true}) {
    _step.selectCefrLevel(level);
    _selectedLevel.value = level;
    if (!announce) return;

    final l10n = L10n.of(context);
    SemanticsService.sendAnnouncement(
      View.of(context),
      level != null
          ? l10n.selectedLanguageLevel(level.title(context))
          : l10n.resetLanguageLevel,
      Directionality.of(context),
    );
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
                Semantics(
                  container: true,
                  child: Column(
                    spacing: 4.0,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        L10n.of(context).pickCefrLevelStepSubtitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _selectedLevel,
                    builder: (context, selectedLevel, _) => Semantics(
                      label: L10n.of(context).difficultyListLabel,
                      container: true,
                      child: ListView.separated(
                        separatorBuilder: (context, i) => SizedBox(height: 4.0),
                        itemCount: levels.length,
                        itemBuilder: (context, i) {
                          final level = levels[i];
                          final selected = selectedLevel == level;
                          return Opacity(
                            opacity: selectedLevel != null && !selected
                                ? 0.5
                                : 1.0,
                            child: MergeSemantics(
                              child: Semantics(
                                selected: selected,
                                child: ElevatedButton(
                                  onPressed: () =>
                                      _setLevel(selected ? null : level),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            level.title(context),
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        level.description(context),
                                        style: theme.textTheme.labelLarge,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _selectedLevel,
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
