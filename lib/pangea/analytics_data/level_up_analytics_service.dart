import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/constructs/construct_repo.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LevelUpAnalyticsService {
  final Client client;
  final Future<void> Function() ensureInitialized;
  final AnalyticsDataService dataService;

  const LevelUpAnalyticsService({
    required this.client,
    required this.ensureInitialized,
    required this.dataService,
  });

  Future<ConstructSummary> getLevelUpAnalytics(
    int lowerLevel,
    int upperLevel,
    DateTime? lastLevelUpTimestamp,
  ) async {
    await ensureInitialized();

    final uses = await dataService.getUses(since: lastLevelUpTimestamp);
    final messages = await _buildMessageContext(uses);

    final userController = MatrixState.pangeaController.userController;
    final request = ConstructSummaryRequest(
      constructs: uses,
      messages: messages,
      userL1: userController.userL1!.langCodeShort,
      userL2: userController.userL2!.langCodeShort,
      lowerLevel: lowerLevel,
      upperLevel: upperLevel,
    );

    final response = await ConstructRepo.generateConstructSummary(request);
    final summary = response.summary;

    summary.levelVocabConstructs = dataService.uniqueConstructsByType(
      ConstructTypeEnum.vocab,
    );
    summary.levelGrammarConstructs = dataService.uniqueConstructsByType(
      ConstructTypeEnum.morph,
    );

    return summary;
  }

  Future<List<Map<String, dynamic>>> _buildMessageContext(
    List<OneConstructUse> uses,
  ) async {
    final Map<String, Set<String>> useEventIds = {};

    for (final use in uses) {
      final roomId = use.metadata.roomId;
      final eventId = use.metadata.eventId;
      if (roomId == null || eventId == null) continue;

      useEventIds.putIfAbsent(roomId, () => {}).add(eventId);
    }

    final List<Map<String, dynamic>> messages = [];

    for (final entry in useEventIds.entries) {
      final room = client.getRoomById(entry.key);
      if (room == null) continue;

      final timeline = await room.getTimeline();

      for (final eventId in entry.value) {
        try {
          final event = await room.getEventById(eventId);
          if (event == null) continue;

          final pangeaEvent = PangeaMessageEvent(
            event: event,
            timeline: timeline,
            ownMessage: room.client.userID == event.senderId,
          );

          if (pangeaEvent.isAudioMessage) {
            final stt = pangeaEvent.getSpeechToTextLocal();
            if (stt == null) continue;
            messages.add({
              'sent': stt.transcript.text,
              'written': stt.transcript.text,
            });
          } else {
            messages.add({
              'sent': pangeaEvent.originalSent?.text ?? pangeaEvent.body,
              'written': pangeaEvent.originalWrittenContent,
            });
          }
        } catch (e, s) {
          ErrorHandler.logError(
            e: e,
            s: s,
            data: {'roomId': entry.key, 'eventId': eventId},
          );
        }
      }
    }

    return messages;
  }
}
