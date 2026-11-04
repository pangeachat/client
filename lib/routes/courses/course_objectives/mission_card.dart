import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/features/quests/quest_progression_resolver.dart';
import 'package:fluffychat/features/quests/repo/quest_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/bold_tonal_button.dart';
import 'package:fluffychat/pangea/common/widgets/pulsing_glow.dart';
import 'package:fluffychat/routes/courses/course_objectives/activity_carousel.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_pacing.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_play_button.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_star.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_bar.dart';
import 'package:fluffychat/routes/courses/course_objectives/mission_xp_ring.dart';
import 'package:fluffychat/routes/courses/course_objectives/progress_shimmer.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The course page's Mission card (#9420, #9559), read top to bottom:
///
/// 1. **Which Mission** — its label and the teacher's due date, with Practice
///    (the secondary action, a tonal pill like the page's others) at the end
///    of the same line, and the teacher's note for it under that line.
/// 2. **What it asks** — the star and can-do statement, a quiet link to the
///    Mission's detail page.
/// 3. **How far along** — where the XP came from (conversation, practice),
///    then a full-width bar of it toward the star in the same golds, its
///    count at the end. The detail page splits it further, by skill.
/// 4. **What to do next** — Play, the one solid, pulsing button, the width of
///    the card it opens and sitting directly on it (the row's first card,
///    labelled "Up next" in Play's colour), then the rest of the Mission's
///    activities.
class MissionCard extends StatelessWidget {
  final QuestObjectiveGroup group;

  /// 1-based position among the course's Missions, or null when unknown.
  final int? index;

  /// The Mission's XP over its threshold; null before progress resolves (or
  /// in a preview), which draws an empty bar with no count.
  final MissionProgress? progress;

  /// The Mission's XP by source, for the legend and the bar's segments; null
  /// before progress resolves (or in a preview), which reads as all zero.
  final MissionXpBreakdown? breakdown;

  /// Null draws Play disabled (no activity to open).
  final VoidCallback? onPlay;

  /// Play's label: "Next activity", "Continue activity" or "Play again".
  final String playLabel;

  /// The name of the activity Play opens, for its tooltip and accessible name.
  final String? playTarget;

  /// Brings the world map to the Mission's pinned activities (a fade, never
  /// a pan or zoom: org course-view doc); null hides Focus.
  final VoidCallback? onFocus;

  /// The Mission's city is not open to the learner yet (org quests doc,
  /// "Progression"): Play gives way to [opensLine], and [onEnterEarly], when
  /// entering a closed city at a cost is on, offers the way in.
  final bool closed;

  /// When the city opens: its date on a dated course, or the Mission before
  /// it on an undated one.
  final String? opensLine;
  final VoidCallback? onEnterEarly;

  /// Drills the Mission's words; null hides Practice — a course in the
  /// learner's base language, whose words aren't a language they're
  /// learning (#9559).
  final VoidCallback? onPractice;

  /// Opens the Mission's detail page from its star and can-do; null leaves
  /// them plain text (a preview has no progress to drill into).
  final VoidCallback? onDetails;

  /// The Mission's activity row, under Play; null draws Play alone.
  final Widget? activities;

  /// The course's language when it isn't the learner's current one (#9559):
  /// its progress counts only in that language, so the legend and bar give
  /// way to [onSwitchLanguage]'s line. Null in the learner's language.
  final String? otherLanguageName;

  /// Offers the switch to [otherLanguageName]; null when the learner can't
  /// switch to it (their base language), which leaves the space empty.
  final VoidCallback? onSwitchLanguage;

  /// Where the language-switch popup anchors: the Mission's statement.
  final String? languageTargetId;

  /// The learner's progress is on its way (a joined course whose resolution
  /// or XP read hasn't landed): the header from its label to its bar
  /// shimmers instead of drawing numbers that would then jump (#9559).
  final bool loading;

  const MissionCard({
    required this.group,
    required this.index,
    required this.progress,
    required this.breakdown,
    required this.onPlay,
    this.onFocus,
    this.closed = false,
    this.opensLine,
    this.onEnterEarly,
    required this.playLabel,
    required this.onPractice,
    this.playTarget,
    this.onDetails,
    this.activities,
    this.otherLanguageName,
    this.onSwitchLanguage,
    this.languageTargetId,
    this.loading = false,
    super.key,
  });

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(24.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context);
    final closedLine = !closed
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              spacing: 8.0,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 16.0,
                  color: scheme.onSurfaceVariant,
                  semanticLabel: l10n.missionNotYetOpen,
                ),
                Expanded(
                  child: Text(
                    [l10n.missionNotYetOpen, ?opensLine].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onEnterEarly case final onEnterEarly?)
                  TextButton(
                    onPressed: onEnterEarly,
                    child: Text(l10n.enterCityEarly),
                  ),
              ],
            ),
          );
    final numbers = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );

    final progress = this.progress;
    final satisfied = progress?.satisfied ?? false;
    final wordCount = group.lemmas.length;
    final dueAt = group.pacing?.dueAt;
    final note = group.pacing?.note;
    final breakdown = this.breakdown ?? MissionXpBreakdown.zero;

    // The course panel's own surface, so the card reads as part of the page;
    // only its brand-purple edge and the hard lip below it set it apart.
    final cardFill = scheme.surface;
    final palette = MissionRingPalette.of(context);

    final xpLabel = progress == null
        ? null
        : l10n.xpTowardObjective(progress.xp, progress.threshold);
    final bar = Semantics(
      label: xpLabel,
      child: ExcludeSemantics(
        child: Tooltip(
          message: progress == null
              ? ''
              : satisfied
              ? l10n.missionStarEarned
              : l10n.xpToYourStar(
                  numbers.format(progress.threshold - progress.xp),
                ),
          child: Row(
            spacing: 10.0,
            children: [
              Expanded(
                child: MissionXpBar(
                  height: 8.0,
                  trackColor: palette.track,
                  gapColor: cardFill,
                  segments: progress == null
                      ? const []
                      : palette.segmentsFor(breakdown, progress.threshold),
                ),
              ),
              if (progress != null)
                Text(
                  l10n.xpOfThreshold(progress.xp, progress.threshold),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final index = this.index;
    final activities = this.activities;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The label is information, so it is text in the brand colour
        // rather than a filled pill that would read as a button; the
        // secondary action takes the end of the line, as on the page's
        // sections.
        Row(
          spacing: 12.0,
          children: [
            // The due date drops to its own line under the label when
            // the two don't fit side by side, rather than squeezing.
            Expanded(
              child: Wrap(
                spacing: 10.0,
                runSpacing: 4.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (index != null)
                    Text(
                      l10n.missionNumber(index).toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  // The Mission's city (org quests doc, "A course is a
                  // trip"), with Focus beside it.
                  if (group.pacing?.city case final city?)
                    _CityChip(
                      name: city.name,
                      closed: closed,
                      onFocus: onFocus,
                    ),
                  // The teacher's due date, beside the label so it is
                  // never behind "See full course plan" (#9559).
                  if (dueAt != null)
                    MissionDueChip(
                      dueAt: dueAt,
                      timeZone: group.pacing?.timeZone,
                    ),
                ],
              ),
            ),
            if (onPractice case final onPractice?)
              BoldTonalButton(
                icon: Symbols.fitness_center,
                label: l10n.practice,
                semanticsLabel:
                    '${l10n.practice}, ${l10n.wordCount(wordCount)}',
                onPressed: onPractice,
                trailing: wordCount > 0
                    ? _CountChip(l10n.wordCount(wordCount))
                    : null,
              ),
          ],
        ),
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 6.0),
          MissionNoteLine(note: note),
        ],
        const SizedBox(height: 6.0),
        _LanguageAnchor(
          targetId: languageTargetId,
          child: _MissionLink(
            statement: group.objective.objective,
            satisfied: satisfied,
            onTap: onDetails,
          ),
        ),
        const SizedBox(height: 8.0),
        if (otherLanguageName != null)
          _SwitchLanguageLine(
            language: otherLanguageName!,
            onTap: onSwitchLanguage,
          )
        else ...[
          // Where the XP came from, in the bar's own golds.
          Wrap(
            spacing: 12.0,
            runSpacing: 4.0,
            children: [
              _XpSourceLegend(
                color: palette.conversation,
                label: l10n.xpFromConversation(
                  numbers.format(breakdown.conversation),
                ),
              ),
              _XpSourceLegend(
                color: palette.practice,
                label: l10n.xpFromPractice(numbers.format(breakdown.practice)),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          bar,
        ],
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardFill,
        borderRadius: _radius,
        border: Border.all(color: scheme.primary, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.45),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14.0, 12.0, 14.0, 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // While progress loads, the whole header — label, statement,
            // legend and bar — is one shimmering block over itself, drawn
            // invisibly at its real size, so nothing jumps when it lands.
            if (loading) ProgressShimmer(child: header) else header,
            const SizedBox(height: 18.0),
            // A city not yet open says so where Play would pulse.
            ?closedLine,
            // Play is the width of the card it opens and sits directly on
            // it under its "Up next", so the two read as one thing.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PulsingGlow(
                enabled: onPlay != null && !satisfied && !closed,
                color: scheme.primary,
                borderRadius: MissionPlayButton.radius,
                child: MissionPlayButton(
                  onPressed: closed ? null : onPlay,
                  label: playLabel,
                  target: playTarget,
                  width: activities == null
                      ? null
                      : ActivityCarousel.defaultCardWidth(context),
                ),
              ),
            ),
            // Flush: the row's own top line holds the "Up next".
            ?activities,
          ],
        ),
      ),
    );
  }
}

/// Registers [child] as the language popup's anchor at [targetId] (#9559);
/// [child] alone when there is no popup to anchor.
class _LanguageAnchor extends StatelessWidget {
  final String? targetId;
  final Widget child;

  const _LanguageAnchor({required this.targetId, required this.child});

  @override
  Widget build(BuildContext context) {
    final id = targetId;
    if (id == null) return child;
    final target = MatrixState.pAnyState.layerLinkAndKey(id);
    return CompositedTransformTarget(
      link: target.link,
      child: KeyedSubtree(key: target.key, child: child),
    );
  }
}

/// Where a course in another language's Mission progress would be (#9559):
/// the progress counts only in that language, so this offers the switch —
/// or, for the learner's base language, which can't be switched to, says
/// why the progress isn't shown. Muted, so it reads as a note rather than as
/// the card's action.
class _SwitchLanguageLine extends StatelessWidget {
  final String language;
  final VoidCallback? onTap;

  const _SwitchLanguageLine({required this.language, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurfaceVariant;
    // Nothing to switch to (the course is in the learner's base language):
    // say why the progress isn't here, as plain text.
    if (onTap == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6.0,
        children: [
          Icon(Icons.translate, size: 16.0, color: ink),
          Expanded(
            child: Text(
              L10n.of(context).missionOtherLanguageNotice(language),
              style: theme.textTheme.labelMedium?.copyWith(color: ink),
            ),
          ),
        ],
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(8.0)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6.0,
              children: [
                Icon(Icons.translate, size: 16.0, color: ink),
                Flexible(
                  child: Text(
                    L10n.of(context).switchLanguageChipLabel(language),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Mission's star and can-do statement, which open its detail page: a quiet
/// link — a chevron at the end and a hover/press wash — so it reads as tappable
/// without competing with Play. Plain text when [onTap] is null.
class _MissionLink extends StatelessWidget {
  final String statement;
  final bool satisfied;
  final VoidCallback? onTap;

  static const double _starSize = 22.0;

  const _MissionLink({
    required this.statement,
    required this.satisfied,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onTap = this.onTap;
    // The star leads the statement: it is this Mission's star — the one the
    // analytics bar counts — there from the start and filled once the Mission
    // is complete (quests.instructions.md, "Stars and goal diamonds").
    final content = Padding(
      // Vertical only, so the star lines up with the label above it.
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6.0,
        children: [
          MissionStar(satisfied: satisfied, size: _starSize),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2.0),
              // Never larger than the course title above the card
              // (PanelHeader.titleStyle).
              child: Text(
                statement,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              size: 20.0,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(10.0)),
        child: content,
      ),
    );
  }
}

/// One source in the XP legend: its gold and its XP.
class _XpSourceLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _XpSourceLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 5.0,
      children: [
        MissionXpSwatch(color: color),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The word count beside Practice.
class _CountChip extends StatelessWidget {
  final String text;

  const _CountChip(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.all(Radius.circular(999.0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 1.0),
        child: Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSecondaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The Mission's city (org quests doc, "A course is a trip") as a chip like
/// the due date's, with Focus beside it: the map fades to the Mission's
/// pinned activities, never pans or zooms (org course-view doc).
class _CityChip extends StatelessWidget {
  final String name;
  final bool closed;
  final VoidCallback? onFocus;
  const _CityChip({required this.name, required this.closed, this.onFocus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final chip = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(6.0, 2.0, 8.0, 2.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 4.0),
                child: Icon(
                  closed ? Icons.lock_outline : Icons.place_outlined,
                  size: 14.0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextSpan(text: name),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    final onFocus = this.onFocus;
    if (onFocus == null) return chip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2.0,
      children: [
        chip,
        IconButton(
          tooltip: l10n.focusMission,
          icon: const Icon(Icons.my_location, size: 18.0),
          visualDensity: VisualDensity.compact,
          onPressed: onFocus,
        ),
      ],
    );
  }
}
