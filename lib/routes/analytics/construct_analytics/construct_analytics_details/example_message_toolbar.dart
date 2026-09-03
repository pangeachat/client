import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/languages/language_service.dart';
import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/firebase_analytics.dart';
import 'package:fluffychat/routes/chat/chat.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/show_token_feedback_dialog.dart';
import 'package:fluffychat/routes/chat/events/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/routes/chat/toolbar/message_selection_overlay.dart';
import 'package:fluffychat/routes/chat/toolbar/message_toolbar_host.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Render-box registry id for a vocab example message chip. Distinct from the
/// raw event id, which a chat panel showing the same message may already have
/// claimed as a GlobalKey.
String analyticsExampleMessageTargetId(String eventId) =>
    'analytics_example_message_$eventId';

/// Hosts the message toolbar overlay on the analytics vocab details page
/// (#8081). Selection state lives in the overlay itself, so the host only
/// closes the overlay entry; there is no chat-side selection to mirror.
class AnalyticsMessageToolbarHost implements MessageToolbarHost {
  final PangeaMessageEvent messageEvent;
  final BuildContext _context;

  AnalyticsMessageToolbarHost({
    required this.messageEvent,
    required BuildContext context,
  }) : _context = context;

  @override
  Room get room => messageEvent.room;

  @override
  Timeline? get timeline => messageEvent.timeline;

  @override
  ChatController? get chatController => null;

  @override
  void setSelectedEvent(Event event) {}

  @override
  void clearSelectedEvents() =>
      MatrixState.pAnyState.closeOverlay("message_toolbar_overlay");

  @override
  Future<void> showTokenFeedbackDialog(
    TokenInfoFeedbackRequestData requestData,
    String langCode,
    PangeaMessageEvent event,
  ) async {
    clearSelectedEvents();
    await TokenFeedbackUtil.showTokenFeedbackDialog(
      _context,
      requestData: requestData,
      langCode: langCode,
      event: event,
    );
  }
}

/// Opens the message toolbar overlay over an example message chip, with the
/// tapped form's token preselected. Reading assistance only: practice, the
/// more menu, and the reaction picker are hidden via
/// [MessageToolbarConfig.analyticsExample].
Future<void> showAnalyticsExampleMessageToolbar({
  required BuildContext context,
  required AnalyticsMessageToolbarHost host,
  required String chipTargetId,
  PangeaToken? selectedToken,
  Set<String>? highlightVocabLemmas,
}) async {
  final messageEvent = host.messageEvent;
  final event = messageEvent.event;
  if (event.redacted ||
      event.text == '' ||
      event.status == EventStatus.sending) {
    return;
  }

  if (!MatrixState.pangeaController.userController.languagesSet) {
    await LanguageService.showDialogOnEmptyLanguage(context);
    return;
  }

  if (!kIsWeb) {
    HapticFeedback.mediumImpact();
  }

  final overlayEntry = MessageSelectionOverlay(
    host: host,
    event: event,
    timeline: messageEvent.timeline,
    initialSelectedToken: selectedToken,
    nextEvent: null,
    prevEvent: null,
    config: MessageToolbarConfig.analyticsExample,
    messageTargetId: chipTargetId,
    highlightVocabLemmas: highlightVocabLemmas,
  );

  OverlayUtil.showOverlay(
    context: context,
    child: overlayEntry,
    displayDetails: CenteredOverlayDisplayDetails(
      onDismiss: host.clearSelectedEvents,
      blurBackground: true,
      backgroundColor: Colors.black,
      // Same key as chat's toolbar, so one can't open over the other.
      overlayKey: "message_toolbar_overlay",
      // The details page renders inside a clipping PanelCard; the overlay
      // must reach the root overlay to cover the whole page.
      rootOverlay: true,
      modalSemanticsLabel: L10n.of(context).readingAssistanceLabel,
    ),
  );

  GoogleAnalytics.openMessageToolbar();
}
