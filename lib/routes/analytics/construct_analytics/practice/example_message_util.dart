import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Internal result class that holds all computed data from building an example message.
class _ExampleMessageResult {
  final List<InlineSpan> displaySpans;
  final List<PangeaToken> includedTokens;
  final String text;
  final int adjustedTargetIndex;

  /// Message offset of [text]'s first character.
  final int textOffset;
  final String? eventId;
  final String? roomId;

  _ExampleMessageResult({
    required this.displaySpans,
    required this.includedTokens,
    required this.text,
    required this.adjustedTargetIndex,
    required this.textOffset,
    this.eventId,
    this.roomId,
  });

  List<InlineSpan> toSpans() => displaySpans;
  AudioExampleMessage toAudioExampleMessage() => AudioExampleMessage(
    tokens: includedTokens,
    eventId: eventId,
    roomId: roomId,
    exampleMessage: ExampleMessageInfo(
      exampleMessage: displaySpans,
      textOffset: textOffset,
    ),
  );
}

class ExampleMessageUtil {
  /// The spans that stand for cut text on either side of an example, which
  /// are not part of the message and are left out of any text that has to
  /// line up with token offsets.
  static const String ellipsisBefore = '… ';
  static const String ellipsisAfter = '…';

  static bool isEllipsisMarker(InlineSpan span) =>
      span is TextSpan &&
      span.style == null &&
      (span.text == ellipsisBefore || span.text == ellipsisAfter);

  /// [savedOnly] picks among the messages saved on this device without asking
  /// the server, for an offline practice session.
  static Future<List<InlineSpan>?> getExampleMessage(
    ConstructUses construct, {
    String? form,
    bool noBold = false,
    bool savedOnly = false,
  }) async {
    final result = await _getExampleMessageResult(
      construct,
      form: form,
      noBold: noBold,
      savedOnly: savedOnly,
    );
    return result?.toSpans();
  }

  /// [maxContextChars] is how much of the message around the target to keep;
  /// the read-aloud exercise asks for more so the target's whole sentence is
  /// there to cut to.
  static Future<AudioExampleMessage?> getAudioExampleMessage(
    ConstructUses construct, {
    String? form,
    bool noBold = false,
    int maxContextChars = defaultMaxContextChars,
  }) async {
    final result = await _getExampleMessageResult(
      construct,
      form: form,
      noBold: noBold,
      maxContextChars: maxContextChars,
    );
    return result?.toAudioExampleMessage();
  }

  static Future<List<List<InlineSpan>>> getExampleMessages(
    ConstructUses construct,
    Client client,
    int maxMessages, {
    bool noBold = false,
  }) async {
    final List<List<InlineSpan>> allSpans = [];
    for (final use in construct.cappedUses) {
      if (allSpans.length >= maxMessages) break;
      final event = await client.getEventByConstructUse(use);
      if (event == null) continue;

      final result = _buildExampleMessage(use.form, event, noBold: noBold);
      if (result != null) {
        allSpans.add(result.toSpans());
      }
    }
    return allSpans;
  }

  static const int defaultMaxContextChars = 100;

  static Future<_ExampleMessageResult?> _getExampleMessageResult(
    ConstructUses construct, {
    String? form,
    bool noBold = false,
    bool savedOnly = false,
    int maxContextChars = defaultMaxContextChars,
  }) async {
    final uses = List<OneConstructUse>.from(construct.cappedUses);
    uses.shuffle(); // Shuffle to get a random example message each time

    for (final use in uses) {
      if (form != null && use.form != form) continue;
      final client = MatrixState.pangeaController.matrixState.client;
      final event = await client.getEventByConstructUse(
        use,
        savedOnly: savedOnly,
      );
      if (event == null) continue;

      final result = _buildExampleMessage(
        use.form,
        event,
        noBold: noBold,
        maxContextChars: maxContextChars,
      );
      if (result != null) return result;
    }
    return null;
  }

  static _ExampleMessageResult? _buildExampleMessage(
    String? form,
    PangeaMessageEvent messageEvent, {
    bool noBold = false,
    int maxContextChars = defaultMaxContextChars,
  }) {
    String? text;
    List<PangeaToken>? tokens;
    int targetTokenIndex = -1;

    if (messageEvent.isAudioMessage) {
      // TOKEN consumer: the example needs per-token spans, so prefer a
      // token-rich representation over the provisional empty-token embed.
      final stt = messageEvent.getSpeechToTextLocal(preferTokens: true);
      if (stt == null) return null;

      tokens = stt.transcript.sttTokens.map((t) => t.token).toList();
      targetTokenIndex = tokens.indexWhere((t) => t.text.content == form);
      text = stt.transcript.text;
    } else {
      tokens = messageEvent.messageDisplayRepresentation?.tokens;
      if (tokens == null || tokens.isEmpty) return null;

      targetTokenIndex = tokens.indexWhere((t) => t.text.content == form);
      text = messageEvent.messageDisplayText;
    }

    if (targetTokenIndex == -1) {
      return null;
    }

    final targetToken = tokens[targetTokenIndex];

    final targetStart = targetToken.text.offset;
    final targetEnd = targetStart + targetToken.text.content.characters.length;

    final totalChars = text.characters.length;

    final beforeAvailable = targetStart;
    final afterAvailable = totalChars - targetEnd;

    // ---------- Dynamic budget split ----------
    int beforeBudget = maxContextChars ~/ 2;
    int afterBudget = maxContextChars - beforeBudget;

    if (beforeAvailable < beforeBudget) {
      afterBudget += beforeBudget - beforeAvailable;
      beforeBudget = beforeAvailable;
    } else if (afterAvailable < afterBudget) {
      beforeBudget += afterBudget - afterAvailable;
      afterBudget = afterAvailable;
    }

    // ---------- BEFORE ----------
    int beforeStartOffset = 0;
    bool trimmedBefore = false;
    int firstIncludedTokenIndex = 0;

    if (beforeAvailable > beforeBudget) {
      final desiredStart = targetStart - beforeBudget;

      for (int i = 0; i < targetTokenIndex; i++) {
        final token = tokens[i];
        final tokenEnd =
            token.text.offset + token.text.content.characters.length;

        if (tokenEnd > desiredStart) {
          beforeStartOffset = token.text.offset;
          firstIncludedTokenIndex = i;
          trimmedBefore = true;
          break;
        }
      }
    }

    final before = text.characters
        .skip(beforeStartOffset)
        .take(targetStart - beforeStartOffset)
        .toString();

    // ---------- AFTER ----------
    int afterEndOffset = totalChars;
    bool trimmedAfter = false;
    int lastIncludedTokenIndex = tokens.length - 1;

    if (afterAvailable > afterBudget) {
      final desiredEnd = targetEnd + afterBudget;

      for (int i = targetTokenIndex + 1; i < tokens.length; i++) {
        final token = tokens[i];
        if (token.text.offset >= desiredEnd) {
          afterEndOffset = token.text.offset;
          lastIncludedTokenIndex = i - 1;
          trimmedAfter = true;
          break;
        }
      }
    }

    final after = text.characters
        .skip(targetEnd)
        .take(afterEndOffset - targetEnd)
        .toString()
        .trimRight();

    final displaySpans = [
      if (trimmedBefore)
        const TextSpan(text: ExampleMessageUtil.ellipsisBefore),
      TextSpan(text: before),
      TextSpan(
        text: targetToken.text.content,
        style: noBold ? null : const TextStyle(fontWeight: FontWeight.bold),
      ),
      TextSpan(text: after),
      if (trimmedAfter) const TextSpan(text: ExampleMessageUtil.ellipsisAfter),
    ];

    // Extract only the tokens that are included in the displayed text
    final includedTokens = tokens.sublist(
      firstIncludedTokenIndex,
      lastIncludedTokenIndex + 1,
    );

    // Adjust target token index relative to the included tokens
    final adjustedTargetIndex = targetTokenIndex - firstIncludedTokenIndex;

    return _ExampleMessageResult(
      displaySpans: displaySpans,
      includedTokens: includedTokens,
      text: text.characters
          .skip(beforeStartOffset)
          .take(afterEndOffset - beforeStartOffset)
          .toString(),
      adjustedTargetIndex: adjustedTargetIndex,
      textOffset: beforeStartOffset,
      eventId: messageEvent.eventId,
      roomId: messageEvent.room.id,
    );
  }
}
