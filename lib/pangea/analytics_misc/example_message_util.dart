import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';

class ExampleMessageUtil {
  static Future<List<InlineSpan>?> getExampleMessage(
    ConstructUses construct,
    Client client, {
    String? form,
  }) async {
    for (final use in construct.cappedUses) {
      if (form != null && use.form != form) continue;

      final event = await client.getEventByConstructUse(use);
      if (event == null) continue;

      final spans = _buildExampleMessage(use.form, event);
      if (spans != null) return spans;
    }

    return null;
  }

  static Future<List<List<InlineSpan>>> getExampleMessages(
    ConstructUses construct,
    Client client,
    int maxMessages,
  ) async {
    final List<List<InlineSpan>> allSpans = [];
    for (final use in construct.cappedUses) {
      if (allSpans.length >= maxMessages) break;
      final event = await client.getEventByConstructUse(use);
      if (event == null) continue;

      final spans = _buildExampleMessage(use.form, event);
      if (spans != null) {
        allSpans.add(spans);
      }
    }
    return allSpans;
  }

  static List<InlineSpan>? _buildExampleMessage(
    String? form,
    PangeaMessageEvent messageEvent,
  ) {
    String? text;
    List<PangeaToken>? tokens;
    int targetTokenIndex = -1;

    if (messageEvent.isAudioMessage) {
      final stt = messageEvent.getSpeechToTextLocal();
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

    const maxContextChars = 100;

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

    if (beforeAvailable > beforeBudget) {
      final desiredStart = targetStart - beforeBudget;

      for (int i = 0; i < targetTokenIndex; i++) {
        final token = tokens[i];
        final tokenEnd =
            token.text.offset + token.text.content.characters.length;

        if (tokenEnd > desiredStart) {
          beforeStartOffset = token.text.offset;
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

    if (afterAvailable > afterBudget) {
      final desiredEnd = targetEnd + afterBudget;

      for (int i = targetTokenIndex + 1; i < tokens.length; i++) {
        final token = tokens[i];
        if (token.text.offset >= desiredEnd) {
          afterEndOffset = token.text.offset;
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

    return [
      if (trimmedBefore) const TextSpan(text: '… '),
      TextSpan(text: before),
      TextSpan(
        text: targetToken.text.content,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      TextSpan(text: after),
      if (trimmedAfter) const TextSpan(text: '…'),
    ];
  }
}
