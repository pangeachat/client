// assistance state is, user has not typed a message, user has typed a message and IGC has not run,
// IGC is running, IGC has run and there are remaining steps (either IT or IGC), or all steps are done
// Or user does not have a subscription

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';

enum AssistanceStateEnum {
  noSub,
  noMessage,
  notFetched,
  fetching,
  fetched,
  suggesting,
  suggestionComplete,
  igcComplete,
  error;

  Color stateColor(BuildContext context) {
    switch (this) {
      case AssistanceStateEnum.noMessage:
      case AssistanceStateEnum.fetched:
        return Colors.grey[400]!;
      case AssistanceStateEnum.error:
        return AppConfig.error;
      case AssistanceStateEnum.noSub:
      case AssistanceStateEnum.notFetched:
      case AssistanceStateEnum.fetching:
      case AssistanceStateEnum.suggesting:
        return Theme.of(context).colorScheme.primary;
      case AssistanceStateEnum.suggestionComplete:
      case AssistanceStateEnum.igcComplete:
        return AppConfig.success;
    }
  }

  /// Never empty: this is the button's accessible name as well as its tooltip.
  String tooltip(BuildContext context) => switch (this) {
    AssistanceStateEnum.noSub => L10n.of(context).writingAssistanceNoSub,
    AssistanceStateEnum.error => L10n.of(context).viewError,
    AssistanceStateEnum.notFetched ||
    AssistanceStateEnum.igcComplete => L10n.of(context).check,
    // The lightbulb states are named for what the button offers (#8904).
    AssistanceStateEnum.suggesting || AssistanceStateEnum.suggestionComplete =>
      L10n.of(context).writingAssistanceSuggestion,
    AssistanceStateEnum.noMessage ||
    AssistanceStateEnum.fetching ||
    AssistanceStateEnum.fetched => L10n.of(context).writingAssistanceNoSub,
  };

  Color sendButtonColor(BuildContext context) {
    switch (this) {
      case AssistanceStateEnum.noMessage:
      case AssistanceStateEnum.fetched:
      case AssistanceStateEnum.suggesting:
        return Theme.of(context).disabledColor;
      case AssistanceStateEnum.noSub:
      case AssistanceStateEnum.error:
      case AssistanceStateEnum.notFetched:
      case AssistanceStateEnum.fetching:
        return Theme.of(context).colorScheme.primary;
      case AssistanceStateEnum.suggestionComplete:
      case AssistanceStateEnum.igcComplete:
        return AppConfig.success;
    }
  }

  bool get allowsFeedback => switch (this) {
    AssistanceStateEnum.notFetched => true,
    AssistanceStateEnum.igcComplete => true,
    AssistanceStateEnum.suggesting => true,
    AssistanceStateEnum.noSub => true,
    AssistanceStateEnum.error => true,
    _ => false,
  };

  /// Whether the suggestion card may stay on screen in this state.
  ///
  /// The suggestion is an offer to fill an empty composer, so the states that
  /// justify the card are the two lightbulb ones: a suggestion waiting, and an
  /// accepted suggestion whose text is now the message. Anything else — above
  /// all the learner typing their own message — withdraws it (#8953). See
  /// writing-assistance.instructions.md.
  bool get keepsSuggestionCardOpen => switch (this) {
    AssistanceStateEnum.suggesting => true,
    AssistanceStateEnum.suggestionComplete => true,
    _ => false,
  };

  bool get showIcon => switch (this) {
    AssistanceStateEnum.noSub => true,
    AssistanceStateEnum.noMessage => true,
    AssistanceStateEnum.notFetched => true,
    AssistanceStateEnum.error => true,
    AssistanceStateEnum.igcComplete => true,
    AssistanceStateEnum.suggesting => true,
    AssistanceStateEnum.suggestionComplete => true,
    _ => false,
  };

  IconData get icon => switch (this) {
    AssistanceStateEnum.error => Icons.error,
    AssistanceStateEnum.suggesting => Icons.lightbulb_outline,
    AssistanceStateEnum.suggestionComplete => Icons.lightbulb_outline,
    _ => Icons.check,
  };
}
