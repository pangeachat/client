import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
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
    PangeaToken? token;
    String? text;

    if (messageEvent.isAudioMessage) {
      final stt = messageEvent.getSpeechToTextLocal();
      if (stt == null) return null;
      final tokens = stt.transcript.sttTokens.map((t) => t.token).toList();
      token = tokens.firstWhereOrNull(
        (token) => token.text.content == form,
      );
      text = stt.transcript.text;
    } else {
      final tokens = messageEvent.messageDisplayRepresentation?.tokens;
      if (tokens == null || tokens.isEmpty) return null;
      token = tokens.firstWhereOrNull(
        (token) => token.text.content == form,
      );
      text = messageEvent.messageDisplayText;
    }

    if (token == null) return null;

    final before = text.characters.take(token.text.offset).toString();
    final after = text.characters
        .skip(token.text.offset + token.text.content.characters.length)
        .toString();

    return [
      TextSpan(text: before),
      TextSpan(
        text: token.text.content,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      TextSpan(text: after),
    ];
  }
}
