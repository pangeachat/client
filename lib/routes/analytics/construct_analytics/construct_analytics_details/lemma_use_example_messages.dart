import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/construct_analytics_details/example_message_toolbar.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/extensions/pangea_event_extension.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/message_content.dart';
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
    return ExampleMessage(messageEvent: messageEvent, tokens: tokens);
  }

  Future<List<ExampleMessage>> _getExampleMessages() => collectExampleMessages(
    widget.construct.uses,
    widget.resolveExampleMessage ?? _resolveExampleMessage,
  );

  /// Walks [uses] newest-first, resolving at most 5 distinct example
  /// messages and recording every used form on its example. Static so the
  /// walk is testable with a fake resolver without pumping the widget
  /// (rendering a [MessageContent] needs the full app bootstrap).
  @visibleForTesting
  static Future<List<ExampleMessage>> collectExampleMessages(
    List<OneConstructUse> uses,
    Future<ExampleMessage?> Function(OneConstructUse use) resolve,
  ) async {
    final Map<String, ExampleMessage> examples = {};
    for (int i = uses.length - 1; i >= 0; i--) {
      final use = uses[i];
      final eventId = use.metadata.eventId;
      final form = use.form;
      if (eventId == null || form == null) continue;

      final resolved = examples[eventId];
      if (resolved != null) {
        // Already resolved this message — just record this use's form (a
        // no-op for repeat uses of the same form).
        resolved.addToken(form);
        continue;
      }

      final example = await resolve(use);
      if (example == null) continue;

      if (example.addToken(form)) examples[eventId] = example;
      if (examples.length > 4) break;
    }

    return examples.values.toList();
  }

  /// The example message as a real chat message bubble. Mirrors the bubble
  /// styling in OverlayMessage / the chat's Message widget (bubble color,
  /// text colors, corner radius, [MessageContent] body) so the toolbar
  /// overlay's bubble lands visually identical over the chip, exactly like
  /// in chat — and so tokens get the chat behaviors (hover underline, click
  /// cursor, tap-to-open preselecting that token).
  Widget _exampleMessageBubble(BuildContext context, ExampleMessage example) {
    final theme = Theme.of(context);
    final messageEvent = example.messageEvent;
    final event = messageEvent.event;
    final displayEvent = event.getDisplayEvent(messageEvent.timeline);
    final ownMessage = messageEvent.ownMessage;

    final textColor = event.isActivityMessage
        ? ThemeData.light().colorScheme.onPrimary
        : ownMessage
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    final linkColor = ownMessage
        ? theme.colorScheme.onPrimary
        : theme.brightness == Brightness.light
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    var color = theme.colorScheme.surfaceContainerHigh;
    if (ownMessage) {
      color = displayEvent.status.isError
          ? Colors.redAccent
          : theme.colorScheme.primary;
    }
    if (event.isActivityMessage) {
      color = theme.brightness == Brightness.dark
          ? theme.colorScheme.onSecondary
          : theme.colorScheme.primary;
    }

    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);
    final targetId = analyticsExampleMessageTargetId(example.eventId);
    final highlightLemmas = {widget.construct.lemma.toLowerCase()};
    final host = AnalyticsMessageToolbarHost(
      messageEvent: messageEvent,
      context: context,
    );

    void openToolbar(PangeaToken? token) => showAnalyticsExampleMessageToolbar(
      context: context,
      host: host,
      selectedToken: token,
      chipTargetId: targetId,
      highlightVocabLemmas: highlightLemmas,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        child: Material(
          key: MatrixState.pAnyState.layerLinkAndKey(targetId).key,
          color: color,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => openToolbar(example.firstUsedToken),
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: FluffyThemes.columnWidth * 1.5,
              ),
              child: MessageContent(
                displayEvent,
                textColor: textColor,
                linkColor: linkColor,
                borderRadius: borderRadius,
                timeline: messageEvent.timeline,
                selected: false,
                pangeaMessageEvent: messageEvent,
                controller: host,
                vocabLemmas: highlightLemmas,
                onTokenClick: openToolbar,
                // These chips render real chat messages. Without their own
                // token target-key namespace they collide with the same event
                // in the open chat timeline (#6803).
                isAnalyticsExample: true,
                useTokenKeys: true,
              ),
            ),
          ),
        ),
      ),
    );
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
              children: snapshot.data!
                  .map((example) => _exampleMessageBubble(context, example))
                  .toList(),
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

/// One example message: the resolved message event, its tokens, and which of
/// its forms this construct actually used. Public (rather than file-private)
/// so the resolver seam in [LemmaUseExampleMessages] can be typed.
class ExampleMessage {
  final PangeaMessageEvent messageEvent;
  final List<PangeaToken> tokens;

  ExampleMessage({required this.messageEvent, required this.tokens});

  String get eventId => messageEvent.eventId;

  final List<PangeaToken> _usedTokens = [];

  /// The first used form by position in the message — the token the toolbar
  /// preselects when the chip itself (not a specific token) is tapped.
  PangeaToken? get firstUsedToken =>
      _usedTokens.sortedBy<num>((token) => token.text.offset).firstOrNull;

  bool addToken(String form) {
    final token = tokens.firstWhereOrNull(
      (token) => token.text.content == form,
    );

    if (token == null || _usedTokens.contains(token)) {
      return false;
    }

    _usedTokens.add(token);
    return true;
  }
}
