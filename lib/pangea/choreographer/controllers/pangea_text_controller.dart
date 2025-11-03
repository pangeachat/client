import 'package:flutter/material.dart';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fluffychat/pangea/choreographer/constants/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/constants/match_rule_ids.dart';
import 'package:fluffychat/pangea/choreographer/controllers/extensions/choreographer_state_extension.dart';
import 'package:fluffychat/pangea/choreographer/enums/pangea_match_status.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_state.dart';
import 'package:fluffychat/pangea/choreographer/widgets/igc/autocorrect_span.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../enums/edit_type.dart';
import 'choreographer.dart';

class PangeaTextController extends TextEditingController {
  final Choreographer choreographer;
  EditType editType = EditType.keyboard;
  String _currentText = '';

  PangeaTextController({
    required this.choreographer,
  }) {
    addListener(() {
      final difference =
          text.characters.length - _currentText.characters.length;

      if (difference > 1 && editType == EditType.keyboard) {
        choreographer.onPaste(
          text.characters
              .getRange(
                _currentText.characters.length,
                text.characters.length,
              )
              .join(),
        );
      }
      _currentText = text;
    });
  }

  bool get exceededMaxLength => text.length >= ChoreoConstants.maxLength;

  TextStyle _underlineStyle(Color color) => TextStyle(
        decoration: TextDecoration.underline,
        decorationColor: color,
        decorationThickness: 5,
      );

  Color _underlineColor(PangeaMatch match) {
    if (match.status == PangeaMatchStatus.automatic) {
      return const Color.fromARGB(187, 132, 96, 224);
    }

    switch (match.match.rule?.id ?? "unknown") {
      case MatchRuleIds.interactiveTranslation:
        return const Color.fromARGB(187, 132, 96, 224);
      case MatchRuleIds.tokenNeedsTranslation:
      case MatchRuleIds.tokenSpanNeedsTranslation:
        return const Color.fromARGB(186, 255, 132, 0);
      default:
        return const Color.fromARGB(149, 255, 17, 0);
    }
  }

  TextStyle _textStyle(
    PangeaMatch match,
    TextStyle? existingStyle,
    bool isOpenMatch,
  ) {
    double opacityFactor = 1.0;
    if (!isOpenMatch) {
      opacityFactor = 0.2;
    }

    final alpha = (255 * opacityFactor).round();
    final style = _underlineStyle(_underlineColor(match).withAlpha(alpha));
    return existingStyle?.merge(style) ?? style;
  }

  void setSystemText(String text, EditType type) {
    editType = type;
    this.text = text;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final SubscriptionStatus canSendStatus = choreographer
        .pangeaController.subscriptionController.subscriptionStatus;
    if (canSendStatus == SubscriptionStatus.shouldShowPaywall &&
        !choreographer.isFetching.value &&
        text.isNotEmpty) {
      return TextSpan(
        text: text,
        style: style?.merge(
          _underlineStyle(
            const Color.fromARGB(187, 132, 96, 224),
          ),
        ),
      );
    } else if (!choreographer.hasIGCTextData || text.isEmpty) {
      return TextSpan(text: text, style: style);
    } else {
      final parts = text.split(choreographer.currentIGCText!);
      if (parts.length == 1 || parts.length > 2) {
        return TextSpan(text: text, style: style);
      }

      final inlineSpans = constructTokenSpan(
        defaultStyle: style,
        onUndo: (match) {
          try {
            choreographer.onUndoReplacement(match);
          } catch (e, s) {
            ErrorHandler.logError(
              e: e,
              s: s,
              level: SentryLevel.warning,
              data: {
                "match": match.toJson(),
              },
            );
            MatrixState.pAnyState.closeOverlay();
            choreographer.clearMatches(e);
          }
        },
      );

      return TextSpan(
        style: style,
        children: [
          ...inlineSpans,
          TextSpan(text: parts[1], style: style),
        ],
      );
    }
  }

  InlineSpan _matchSpan(
    PangeaMatchState match,
    TextStyle style,
    VoidCallback onUndo,
  ) {
    if (match.updatedMatch.status == PangeaMatchStatus.automatic) {
      final span = choreographer.currentIGCText!.characters
          .getRange(
            match.updatedMatch.match.offset,
            match.updatedMatch.match.offset + match.updatedMatch.match.length,
          )
          .toString();

      final originalText = match.originalMatch.match.fullText.characters
          .getRange(
            match.originalMatch.match.offset,
            match.originalMatch.match.offset + match.originalMatch.match.length,
          )
          .toString();

      return AutocorrectSpan(
        transformTargetId:
            "autocorrection_${match.updatedMatch.match.offset}_${match.updatedMatch.match.length}",
        currentText: span,
        originalText: originalText,
        onUndo: onUndo,
        style: style,
      );
    } else {
      return TextSpan(
        text: choreographer.currentIGCText!.characters
            .getRange(
              match.updatedMatch.match.offset,
              match.updatedMatch.match.offset + match.updatedMatch.match.length,
            )
            .toString(),
        style: style,
      );
    }
  }

  /// Returns a list of [TextSpan]s used to display the text in the input field
  /// with the appropriate styling for each error match.
  List<InlineSpan> constructTokenSpan({
    required void Function(PangeaMatchState) onUndo,
    TextStyle? defaultStyle,
  }) {
    final automaticMatches = choreographer.closedIGCMatches
            ?.where((m) => m.updatedMatch.status == PangeaMatchStatus.automatic)
            .toList() ??
        [];

    final textSpanMatches = [
      ...choreographer.openIGCMatches ?? [],
      ...automaticMatches,
    ]..sort(
        (a, b) =>
            a.updatedMatch.match.offset.compareTo(b.updatedMatch.match.offset),
      );

    final currentText = choreographer.currentIGCText!;
    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final match in textSpanMatches) {
      if (cursor < match.updatedMatch.match.offset) {
        final text = currentText.characters
            .getRange(cursor, match.updatedMatch.match.offset)
            .toString();
        spans.add(TextSpan(text: text, style: defaultStyle));
      }

      final openMatch = choreographer.openMatch?.updatedMatch.match;
      final style = _textStyle(
        match.updatedMatch,
        defaultStyle,
        openMatch != null &&
            openMatch.offset == match.updatedMatch.match.offset &&
            openMatch.length == match.updatedMatch.match.length,
      );

      spans.add(_matchSpan(match, style, () => onUndo.call(match)));
      cursor =
          match.updatedMatch.match.offset + match.updatedMatch.match.length;
    }

    if (cursor < currentText.characters.length) {
      spans.add(
        TextSpan(
          text: currentText.characters
              .getRange(cursor, currentText.characters.length)
              .toString(),
          style: defaultStyle,
        ),
      );
    }

    return spans;
  }
}
