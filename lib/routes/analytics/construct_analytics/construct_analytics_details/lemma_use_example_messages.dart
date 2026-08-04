import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/example_message_toolbar.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LemmaUseExampleMessages extends StatefulWidget {
  final ConstructUses construct;
  final Client client;

  /// Testability seam: resolves one construct use to its example message.
  /// Production leaves this null and uses [getEventByConstructUse] plus the
  /// event's display representation.
  @visibleForTesting
  final Future<ExampleMessage?> Function(OneConstructUse use)?
  resolveExampleMessage;

  const LemmaUseExampleMessages({
    super.key,
    required this.construct,
    required this.client,
    this.resolveExampleMessage,
  });

  @override
  State<LemmaUseExampleMessages> createState() =>
      LemmaUseExampleMessagesState();
}

class LemmaUseExampleMessagesState extends State<LemmaUseExampleMessages> {
  late Future<List<ExampleMessage>> _examplesFuture;

  @override
  void initState() {
    super.initState();
    _examplesFuture = _getExampleMessages();
  }

  @override
  void didUpdateWidget(covariant LemmaUseExampleMessages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.construct.id != widget.construct.id) {
      _examplesFuture = _getExampleMessages();
    }
  }

  Future<ExampleMessage?> _resolveExampleMessage(OneConstructUse use) async {
    final messageEvent = await widget.client.getEventByConstructUse(use);
    if (messageEvent == null) return null;

    final tokens = messageEvent.messageDisplayRepresentation?.tokens;
    if (tokens == null || tokens.isEmpty) return null;
    return ExampleMessage(
      messageEvent: messageEvent,
      message: messageEvent.messageDisplayText,
      tokens: tokens,
    );
  }

  Future<List<ExampleMessage>> _getExampleMessages() async {
    final resolve = widget.resolveExampleMessage ?? _resolveExampleMessage;
    final Map<String, ExampleMessage> examples = {};
    final uses = widget.construct.uses;
    for (int i = uses.length - 1; i >= 0; i--) {
      final use = uses[i];
      final eventId = use.metadata.eventId;
      final form = use.form;
      if (eventId == null || form == null) continue;

      final resolved = examples[eventId];
      if (resolved != null) {
        // Already resolved this message — just bold this use's form (a no-op
        // for repeat uses of the same form). Re-resolving here would discard
        // the forms already bolded on the example.
        resolved.addToken(form);
        continue;
      }

      final example = await resolve(use);
      if (example == null) continue;

      if (example.addToken(form)) examples[eventId] = example;
      if (examples.length > 4) break;
    }

    final List<ExampleMessage> result = [];
    for (final example in examples.values) {
      try {
        example.spans = example.getTextSpans();
        result.add(example);
      } catch (e, s) {
        ErrorHandler.logError(
          e: e,
          s: s,
          data: {
            "message": example.message,
            ModelKey.tokens: example.tokens
                .map((t) => t.text.toJson())
                .toList(),
          },
        );
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _examplesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Align(
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: snapshot.data!.map((example) {
                final targetId = analyticsExampleMessageTargetId(
                  example.eventId,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    button: true,
                    child: Material(
                      key: MatrixState.pAnyState.layerLinkAndKey(targetId).key,
                      color: widget.construct.lemmaCategory.color(context),
                      borderRadius: BorderRadius.circular(4),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => showAnalyticsExampleMessageToolbar(
                          context: context,
                          messageEvent: example.messageEvent,
                          selectedToken: example.firstBoldedToken,
                          chipTargetId: targetId,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryFixed,
                                fontSize:
                                    AppSettings.fontSizeFactor.value *
                                    AppConfig.messageFontSize,
                              ),
                              children: example.spans,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        } else {
          return const Column(
            children: [
              SizedBox(height: 10),
              CircularProgressIndicator.adaptive(strokeWidth: 2),
            ],
          );
        }
      },
    );
  }
}

/// One example message chip: the resolved message event, its display text,
/// its tokens, and which forms to bold. Public (rather than file-private) so
/// the resolver seam in [LemmaUseExampleMessages] can be typed.
class ExampleMessage {
  final PangeaMessageEvent messageEvent;
  final String message;
  final List<PangeaToken> tokens;

  /// Styled spans for the chip, precomputed by [getTextSpans] once all forms
  /// are added (it throws on token/text mismatch, so failed examples are
  /// dropped before rendering).
  List<TextSpan> spans = [];

  ExampleMessage({
    required this.messageEvent,
    required this.message,
    required this.tokens,
  });

  String get eventId => messageEvent.eventId;

  final List<PangeaToken> _boldedTokens = [];

  /// The first bolded form by position in the message — the token the
  /// toolbar preselects when the chip is tapped.
  PangeaToken? get firstBoldedToken =>
      _boldedTokens.sortedBy<num>((token) => token.text.offset).firstOrNull;

  bool addToken(String form) {
    final token = tokens.firstWhereOrNull(
      (token) => token.text.content == form,
    );

    if (token == null || _boldedTokens.contains(token)) {
      return false;
    }

    _boldedTokens.add(token);
    return true;
  }

  /// Get a list of text spans with styling to indicate the matching tokens.
  List<TextSpan> getTextSpans() {
    int characterPointer = 0;
    final List<TextSpan> spans = [];

    final sortedTokens = [..._boldedTokens]
      ..sort((a, b) => a.text.offset.compareTo(b.text.offset));

    for (final token in sortedTokens) {
      if (token.text.offset > characterPointer) {
        final beforeText = message.characters
            .skip(characterPointer)
            .take(token.text.offset - characterPointer)
            .toString();
        spans.add(TextSpan(text: beforeText));
      }

      characterPointer = token.text.offset;
      final tokenText = message.characters
          .skip(characterPointer)
          .take(token.text.length)
          .toString();

      if (tokenText != token.text.content) {
        throw StateError(
          "Token text mismatch: expected '${token.text.content}', got '$tokenText'",
        );
      }

      spans.add(
        TextSpan(
          text: tokenText,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );

      characterPointer = token.text.offset + token.text.length;
    }

    if (characterPointer < message.length) {
      final afterText = message.characters
          .skip(characterPointer)
          .take(message.length - characterPointer)
          .toString();
      spans.add(TextSpan(text: afterText));
    }

    return spans;
  }
}
