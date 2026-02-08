import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/choreographer/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/igc/autocorrect_span.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_state_model.dart';
import 'package:fluffychat/pangea/choreographer/igc/pangea_match_status_enum.dart';
import 'package:fluffychat/pangea/choreographer/igc/replacement_type_enum.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../choreographer.dart';
import 'edit_type_enum.dart';

class PangeaTextController extends TextEditingController {
  final Choreographer choreographer;
  EditTypeEnum editType = EditTypeEnum.keyboard;
  String _currentText = '';

  PangeaTextController({
    required this.choreographer,
  }) {
    addListener(_onTextChanged);
  }

  bool get exceededMaxLength => text.length >= ChoreoConstants.maxLength;

  TextStyle _underlineStyle(Color color) => TextStyle(
        decoration: TextDecoration.underline,
        decorationColor: color,
        decorationThickness: 5,
      );

  Color _underlineColor(PangeaMatch match, BuildContext context) {
    // Automatic corrections use primary color
    if (match.status == PangeaMatchStatusEnum.automatic) {
      return AppConfig.primaryColor.withOpacity(0.7);
    }

    // Use type-based coloring
    return match.match.type.underlineColor(context);
  }

  TextStyle _textStyle(
    PangeaMatch match,
    TextStyle? existingStyle,
    bool isOpenMatch,
    BuildContext context,
  ) {
    double opacityFactor = 1.0;
    if (!isOpenMatch) {
      opacityFactor = 0.2;
    }

    final alpha = (255 * opacityFactor).round();
    final style = _underlineStyle(_underlineColor(match, context).withAlpha(alpha));
    return existingStyle?.merge(style) ?? style;
  }

  void setSystemText(String newText, EditTypeEnum type) {
    editType = type;
    text = newText;
  }

  void _onTextChanged() {
    final diff = text.characters.length - _currentText.characters.length;
    if (diff > 1 && editType == EditTypeEnum.keyboard) {
      final pastedText = text.characters.skip(_currentText.characters.length).take(diff).join();
      choreographer.onPaste(pastedText);
    }
    _currentText = text;
  }

  void _onUndo(PangeaMatchState match) {
    try {
      choreographer.igcController.updateMatch(
        match,
        PangeaMatchStatusEnum.undo,
      );
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
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final subscription = MatrixState.pangeaController.subscriptionController.subscriptionStatus;

    if (subscription == SubscriptionStatus.shouldShowPaywall) {
      return _buildPaywallSpan(style);
    }

    if (choreographer.igcController.currentText == null) {
      return TextSpan(text: text, style: style);
    }

    final parts = text.split(choreographer.igcController.currentText!);
    if (parts.length != 2) {
      return TextSpan(text: text, style: style);
    }

    return TextSpan(
      style: style,
      children: [
        ..._buildTokenSpan(defaultStyle: style, context: context),
        TextSpan(text: parts[1], style: style),
      ],
    );
  }

  TextSpan _buildPaywallSpan(TextStyle? style) => TextSpan(
        text: text,
        style: style?.merge(
          _underlineStyle(const Color.fromARGB(187, 132, 96, 224)),
        ),
      );

  InlineSpan _buildMatchSpan(
    PangeaMatchState match,
    TextStyle style,
  ) {
    final span = choreographer.igcController.currentText!.characters
        .getRange(
          match.updatedMatch.match.offset,
          match.updatedMatch.match.offset + match.updatedMatch.match.length,
        )
        .toString();

    if (match.updatedMatch.status == PangeaMatchStatusEnum.automatic) {
      final originalText = match.originalMatch.match.fullText.characters
          .getRange(
            match.originalMatch.match.offset,
            match.originalMatch.match.offset + match.originalMatch.match.length,
          )
          .toString();

      return AutocorrectSpan(
        transformTargetId: "autocorrection_${match.updatedMatch.match.offset}_${match.updatedMatch.match.length}",
        currentText: span,
        originalText: originalText,
        onUndo: () => _onUndo(match),
        style: style,
      );
    } else {
      return TextSpan(
        text: span,
        style: style,
      );
    }
  }

  /// Returns a list of [TextSpan]s used to display the text in the input field
  /// with the appropriate styling for each error match.
  List<InlineSpan> _buildTokenSpan({
    TextStyle? defaultStyle,
    required BuildContext context,
  }) {
    final textSpanMatches = [
      ...choreographer.igcController.openMatches,
      ...choreographer.igcController.recentAutomaticCorrections,
    ]..sort(
        (a, b) => a.updatedMatch.match.offset.compareTo(b.updatedMatch.match.offset),
      );

    final currentText = choreographer.igcController.currentText!;
    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final match in textSpanMatches) {
      if (cursor < match.updatedMatch.match.offset) {
        final text = currentText.characters.getRange(cursor, match.updatedMatch.match.offset).toString();
        spans.add(TextSpan(text: text, style: defaultStyle));
      }

      final openMatch = choreographer.igcController.currentlyOpenMatch?.updatedMatch.match;
      final style = _textStyle(
        match.updatedMatch,
        defaultStyle,
        openMatch != null &&
            openMatch.offset == match.updatedMatch.match.offset &&
            openMatch.length == match.updatedMatch.match.length,
        context,
      );

      spans.add(_buildMatchSpan(match, style));
      cursor = match.updatedMatch.match.offset + match.updatedMatch.match.length;
    }

    if (cursor < currentText.characters.length) {
      spans.add(
        TextSpan(
          text: currentText.characters.getRange(cursor, currentText.characters.length).toString(),
          style: defaultStyle,
        ),
      );
    }

    return spans;
  }
}
