import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';

class ExampleMessageUtil {
  static Future<List<InlineSpan>?> getExampleMessage(
    ConstructUses construct,
    Client client,
  ) async {
    for (final use in construct.cappedUses) {
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
    final tokens = messageEvent.messageDisplayRepresentation?.tokens;
    if (tokens == null || tokens.isEmpty) return null;
    final token = tokens.firstWhereOrNull(
      (token) => token.text.content == form,
    );
    if (token == null) return null;

    final text = messageEvent.messageDisplayText;
    final tokenText = token.text.content;
    int tokenIndex = text.indexOf(tokenText);
    if (tokenIndex == -1) return null;

    final beforeSubstring = text.substring(0, tokenIndex);
    if (beforeSubstring.length != beforeSubstring.characters.length) {
      tokenIndex = beforeSubstring.characters.length;
    }

    final int tokenLength = tokenText.characters.length;
    final before = text.characters.take(tokenIndex).toString();
    final after = text.characters.skip(tokenIndex + tokenLength).toString();
    return [
      TextSpan(text: before),
      TextSpan(
        text: tokenText,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      TextSpan(text: after),
    ];
  }
}
