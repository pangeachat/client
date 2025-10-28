import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/choreographer/controllers/error_service.dart';
import 'package:fluffychat/pangea/choreographer/enums/pangea_match_status.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_state.dart';
import 'package:fluffychat/pangea/choreographer/utils/match_style_util.dart';
import 'package:fluffychat/pangea/choreographer/widgets/igc/autocorrect_span.dart';
import 'package:fluffychat/pangea/choreographer/widgets/igc/paywall_card.dart';
import 'package:fluffychat/pangea/choreographer/widgets/igc/span_card.dart';
import 'package:fluffychat/pangea/subscription/controllers/subscription_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../../common/utils/overlay.dart';
import '../enums/edit_type.dart';
import 'choreographer.dart';

class PangeaTextController extends TextEditingController {
  Choreographer choreographer;

  EditType editType = EditType.keyboard;
  PangeaTextController({
    String? text,
    required this.choreographer,
  }) {
    text ??= '';
    this.text = text;
  }

  static const int maxLength = 1000;
  bool get exceededMaxLength => text.length >= maxLength;

  bool forceKeepOpen = false;

  void setSystemText(String text, EditType type) {
    editType = type;
    this.text = text;
  }

  void onInputTap(BuildContext context, {required FocusNode fNode}) {
    fNode.requestFocus();
    forceKeepOpen = true;
    if (!context.mounted) {
      debugger(when: kDebugMode);
      return;
    }

    // show the paywall if appropriate
    if (choreographer
                .pangeaController.subscriptionController.subscriptionStatus ==
            SubscriptionStatus.shouldShowPaywall &&
        !choreographer.isFetching &&
        text.isNotEmpty) {
      PaywallCard.show(context, choreographer.chatController);
      return;
    }

    // if there is no igc text data, then don't do anything
    if (choreographer.igc.igcTextData == null) return;

    // debugPrint(
    //     "onInputTap matches are ${choreographer.igc.igcTextData?.matches.map((e) => e.match.rule.id).toList().toString()}");

    // if user is just trying to get their cursor into the text input field to add soemthing,
    // then don't interrupt them
    if (selection.baseOffset >= text.length) {
      return;
    }

    final match = choreographer.igc.igcTextData!.getMatchByOffset(
      selection.baseOffset,
    );
    if (match == null) return;

    // if autoplay on and it start then just start it
    if (match.updatedMatch.isITStart) {
      return choreographer.onITStart(match);
    }

    MatrixState.pAnyState.closeAllOverlays();
    OverlayUtil.showPositionedCard(
      overlayKey:
          "span_card_overlay_${match.updatedMatch.match.offset}_${match.updatedMatch.match.length}",
      context: context,
      maxHeight: 400,
      maxWidth: 350,
      cardToShow: SpanCard(
        match: match,
        choreographer: choreographer,
      ),
      transformTargetId: choreographer.inputTransformTargetKey,
      onDismiss: () => choreographer.setState(),
      ignorePointer: true,
      isScrollable: false,
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // If the composing range is out of range for the current text, ignore it to
    // preserve the tree integrity, otherwise in release mode a RangeError will
    // be thrown and this EditableText will be built with a broken subtree.
    // debugPrint("composing? $withComposing");
    // if (!value.isComposingRangeValid || !withComposing) {
    //   debugPrint("just returning straight text");
    //   // debugger(when: kDebugMode);
    //   return TextSpan(style: style, text: text);
    // }
    // if (value.isComposingRangeValid) {
    //   debugPrint("composing before ${value.composing.textBefore(value.text)}");
    //   debugPrint("composing inside ${value.composing.textInside(value.text)}");
    //   debugPrint("composing after ${value.composing.textAfter(value.text)}");
    // }

    final SubscriptionStatus canSendStatus = choreographer
        .pangeaController.subscriptionController.subscriptionStatus;
    if (canSendStatus == SubscriptionStatus.shouldShowPaywall &&
        !choreographer.isFetching &&
        text.isNotEmpty) {
      return TextSpan(
        text: text,
        style: style?.merge(
          MatchStyleUtil.underlineStyle(
            const Color.fromARGB(187, 132, 96, 224),
          ),
        ),
      );
    } else if (choreographer.igc.igcTextData == null || text.isEmpty) {
      return TextSpan(text: text, style: style);
    } else {
      final parts = text.split(choreographer.igc.igcTextData!.currentText);

      if (parts.length == 1 || parts.length > 2) {
        return TextSpan(text: text, style: style);
      }

      List<InlineSpan> inlineSpans = [];
      try {
        inlineSpans = constructTokenSpan(
          defaultStyle: style,
          onUndo: choreographer.onUndoReplacement,
        );
      } catch (e) {
        choreographer.errorService.setError(
          ChoreoError(raw: e),
        );
        inlineSpans = [TextSpan(text: text, style: style)];
        choreographer.igc.clear();
      }

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
      final span = choreographer.igc.igcTextData!.currentText.characters
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
        text: choreographer.igc.igcTextData!.currentText.characters
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
    final automaticMatches = choreographer.igc.igcTextData!.closedMatches
        .where((m) => m.updatedMatch.status == PangeaMatchStatus.automatic)
        .toList();

    final textSpanMatches = [
      ...choreographer.igc.igcTextData!.openMatches,
      ...automaticMatches,
    ]..sort(
        (a, b) =>
            a.updatedMatch.match.offset.compareTo(b.updatedMatch.match.offset),
      );

    final currentText = choreographer.igc.igcTextData!.currentText;

    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final match in textSpanMatches) {
      if (cursor < match.updatedMatch.match.offset) {
        final text = currentText.characters
            .getRange(cursor, match.updatedMatch.match.offset)
            .toString();
        spans.add(TextSpan(text: text, style: defaultStyle));
      }

      final openMatch =
          choreographer.igc.igcTextData?.openMatch?.updatedMatch.match;
      final style = MatchStyleUtil.textStyle(
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
