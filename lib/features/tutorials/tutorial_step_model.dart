import 'package:flutter/material.dart';

import 'package:fluffychat/features/tutorials/tutorial_copy.dart';
import 'package:fluffychat/features/tutorials/tutorial_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';

class TutorialStep {
  final TutorialEnum type;
  final int index;
  final TutorialStepData data;
  final TutorialStepStyle style;

  const TutorialStep({
    required this.type,
    required this.index,
    required this.data,
    required this.style,
  });
}

/// What the host supplies for one step: which widgets the spotlight lights, what
/// happens when the learner advances, and — for a step the learner has to
/// perform themselves — what the step is waiting for.
class TutorialStepData {
  /// The widgets to light, by target id — resolved from the overlay registry
  /// every frame. Empty, with no [spotlightRects] either, means no spotlight at
  /// all: the bot card sits centered over the darkened screen, for a step that
  /// is about the app rather than about anything on it.
  final List<String> targetKeys;

  /// Where to light, when the host has to work the geometry out itself instead
  /// of a widget carrying a target id. Called every frame, so it tracks.
  ///
  /// Map pins are why this exists: the marker layer mounts the same pin once
  /// per repeated copy of the world, so no one mount site can claim a target id
  /// ([TutorialTarget]). The map projects its own pins through the live camera
  /// instead.
  final List<Rect> Function()? spotlightRects;

  /// Runs when the learner taps through. A tap step does its own work here —
  /// opening the toolbar, expanding the goals, opening a panel — and
  /// [canShowNextStep] then confirms the work landed.
  final Future<void> Function()? onTap;

  final bool Function() canShowNextStep;

  /// Set on a step the learner must perform themselves. Its presence is what
  /// makes the step armed: the overlay stops absorbing taps, and the step
  /// advances when [TutorialStepArming.isSatisfied] turns true rather than on a
  /// tap. See tutorials.instructions.md.
  final TutorialStepArming? arming;

  /// Whether the surface this step belongs to is still in front of the learner.
  /// False means get out of the way — the same thing a vanished target means,
  /// for a step whose target cannot vanish because it has none, or whose target
  /// is geometry rather than a widget. Without it a card that tracks nothing
  /// would follow the learner onto every other screen.
  final bool Function()? surfaceIsVisible;

  /// Runtime values this step's copy needs — a greeting in the learner's target
  /// language, a language name, whether anything was found. The copy itself
  /// stays in the step's template; only the values come from here, so there is
  /// still exactly one place a string is written.
  ///
  /// Called on every build rather than read once at launch: a step can be shown
  /// long after its tutorial started, and copy resolved at launch would describe
  /// a stale world (whether any two-role pin was in view, say).
  final List<String> Function()? tooltipArgs;

  /// A word inside this step's copy that is shown as a tappable vocabulary
  /// word rather than as text. Only the welcome step's L2 greeting today.
  ///
  /// Data, not a widget: the host resolves the word (it owns the network call
  /// that tokenizes it) and the tooltip owns how a word is drawn, so neither
  /// has to know the other's job. Null — the fallback paths, where the greeting
  /// ended up in a language the learner already speaks — renders as plain text.
  final TutorialGreeting? Function()? wordBubble;

  List<String> get resolvedTooltipArgs => tooltipArgs?.call() ?? const [];

  TutorialStepData({
    this.targetKeys = const [],
    this.spotlightRects,
    this.onTap,
    required this.canShowNextStep,
    this.arming,
    this.tooltipArgs,
    this.surfaceIsVisible,
    this.wordBubble,
  });

  /// Convenience for the common single-target step.
  TutorialStepData.single({
    required String targetKey,
    this.onTap,
    required this.canShowNextStep,
    this.arming,
    this.tooltipArgs,
    this.surfaceIsVisible,
    this.wordBubble,
  }) : targetKeys = [targetKey],
       spotlightRects = null;

  bool get isArmed => arming != null;

  bool get hasSpotlight => targetKeys.isNotEmpty || spotlightRects != null;
}

/// What an armed step waits for. [signal] fires whenever the answer might have
/// changed; [isSatisfied] is the answer. Watched by the controller rather than
/// the overlay, because an armed step deliberately outlives the overlay — the
/// learner is off doing the thing, and the tutorial resumes when they have.
class TutorialStepArming {
  final Listenable signal;
  final bool Function() isSatisfied;

  const TutorialStepArming({required this.signal, required this.isSatisfied});
}

/// What tapping a branch step's choice does.
enum TutorialChoiceOutcome {
  /// Carry on to the next step.
  advance,

  /// End this tutorial and mark it seen. The learner was asked and said no, so
  /// it should not come back.
  decline,
}

/// One labelled answer on a branch step.
class TutorialStepChoice {
  final String Function(L10n) label;
  final TutorialChoiceOutcome outcome;

  const TutorialStepChoice({required this.label, required this.outcome});
}

/// One step's copy and geometry, declared per tutorial in
/// [TutorialStepTemplates]. The length of a tutorial's template list IS its
/// step count — see [TutorialEnum.stepCount] — so there is nowhere for the
/// count, the tooltip sizes, and the copy to drift apart.
class TutorialStepTemplate {
  /// Receives the app's [L10n] and whatever [TutorialStepData.tooltipArgs] the
  /// host supplied, so copy that varies at runtime still lives here.
  final String Function(L10n l10n, List<String> args) tooltip;
  final Size tooltipSize;
  final double? borderRadius;
  final double? padding;

  /// Whether this step darkens what is behind it.
  ///
  /// False paints no scrim and no cut-outs, and sends the card to the bottom of
  /// the screen rather than the middle — for a step about the whole screen,
  /// darkening the thing it describes works against it. Purely visual: a tap
  /// anywhere still advances, exactly as on a dimmed step. What hands the screen
  /// back to the learner is [TutorialStepData.arming], not this.
  final bool dimsBackground;

  /// Present on a **branch** step: the step asks a question and the learner
  /// answers by picking one of these instead of tapping through. Declared here
  /// with the copy, since which answers exist is part of what the step says.
  final List<TutorialStepChoice> choices;

  const TutorialStepTemplate({
    required this.tooltip,
    required this.tooltipSize,
    this.borderRadius,
    this.padding,
    this.choices = const [],
    this.dimsBackground = true,
  });

  TutorialStepStyle resolve(L10n l10n, List<String> args) => TutorialStepStyle(
    tooltip: tooltip(l10n, args),
    tooltipSize: tooltipSize,
    borderRadius: borderRadius,
    padding: padding,
    choices: [
      for (final choice in choices)
        (label: choice.label(l10n), outcome: choice.outcome),
    ],
    dimsBackground: dimsBackground,
  );
}

/// A [TutorialStepTemplate] with its copy resolved for the current locale.
class TutorialStepStyle {
  final String tooltip;
  final Size tooltipSize;
  final double? borderRadius;
  final double? padding;

  /// Non-empty on a branch step. A tap anywhere else must do nothing while
  /// these are showing, or a tap aimed at a button advances past the question.
  final List<({String label, TutorialChoiceOutcome outcome})> choices;

  /// See [TutorialStepTemplate.dimsBackground].
  final bool dimsBackground;

  const TutorialStepStyle({
    required this.tooltip,
    required this.tooltipSize,
    this.borderRadius,
    this.padding,
    this.choices = const [],
    this.dimsBackground = true,
  });

  bool get isBranch => choices.isNotEmpty;
}
