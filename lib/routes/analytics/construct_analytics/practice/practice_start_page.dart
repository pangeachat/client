import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_identifier.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/learning_skills_enum.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_skills_store.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_start_emojis.dart';

/// What a fresh practice session shows before its clock starts: how many
/// words or grammar points it practices, those words' emojis, the
/// exercise-type chips for vocab, and one big Start. See
/// practice-exercises.instructions.md, "Start page".
class PracticeStartPage extends StatelessWidget {
  final ConstructTypeEnum type;
  final int count;

  /// The words whose emojis the row shows; empty for grammar.
  final List<ConstructIdentifier> emojiWords;
  final bool offline;

  /// The exercise types on, and those the session has words for.
  final Set<LearningSkillsEnum> skills;
  final Set<LearningSkillsEnum> availableSkills;
  final ValueChanged<Set<LearningSkillsEnum>> onSkillsChanged;
  final VoidCallback onStart;

  const PracticeStartPage({
    required this.type,
    required this.count,
    required this.emojiWords,
    required this.offline,
    required this.skills,
    required this.availableSkills,
    required this.onSkillsChanged,
    required this.onStart,
    super.key,
  });

  /// At least one type stays on.
  void _toggle(LearningSkillsEnum skill, bool on) {
    final next = {...skills};
    on ? next.add(skill) : next.remove(skill);
    if (next.isEmpty) return;
    onSkillsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 16.0, bottom: 56.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emojiWords.isNotEmpty)
              PracticeStartEmojis(words: emojiWords, offline: offline),
            MergeSemantics(
              child: Column(
                spacing: 4.0,
                children: [
                  Text(
                    '$count',
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    type == ConstructTypeEnum.vocab
                        ? l10n.practiceStartWordCount(count)
                        : l10n.practiceStartGrammarCount(count),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (type == ConstructTypeEnum.vocab)
              Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: Semantics(
                  container: true,
                  label: l10n.practiceStartExerciseTypes,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: [
                      for (final skill in PracticeSkillsStore.vocabSkills)
                        FilterChip(
                          // The checkmark takes the icon's place when on.
                          avatar: skills.contains(skill)
                              ? null
                              : Icon(skill.icon),
                          label: Text(skill.tooltip(context)),
                          selected: skills.contains(skill),
                          showCheckmark: true,
                          onSelected: availableSkills.contains(skill)
                              ? (on) => _toggle(skill, on)
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 48.0),
            FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                minimumSize: const Size(240.0, 64.0),
                textStyle: theme.textTheme.titleLarge,
              ),
              child: Text(l10n.start),
            ),
          ],
        ),
      ),
    );
  }
}
