import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/constructs/construct_identifier.dart';
import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_generation_repo.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_session_model.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_session_repo.dart';
import 'package:fluffychat/pangea/vocab_practice/vocab_practice_view.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class SessionLoader extends AsyncLoader<VocabPracticeSessionModel> {
  @override
  Future<VocabPracticeSessionModel> fetch() =>
      VocabPracticeSessionRepo.currentSession;
}

class VocabPractice extends StatefulWidget {
  const VocabPractice({super.key});

  @override
  VocabPracticeState createState() => VocabPracticeState();
}

class VocabPracticeState extends State<VocabPractice> {
  final SessionLoader sessionLoader = SessionLoader();

  PracticeActivityModel? currentActivity;
  bool isLoadingActivity = true;
  String? activityError;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    sessionLoader.dispose();
    if (isFinished) {
      VocabPracticeSessionRepo.clearSession();
    }
    super.dispose();
  }

  bool get isComplete =>
      sessionLoader.isLoaded && sessionLoader.value!.hasCompletedCurrentGroup;

  bool get isFinished =>
      sessionLoader.isLoaded && sessionLoader.value!.isFinshed;

  Future<void> _waitForAnalytics() async {
    if (!MatrixState.pangeaController.getAnalytics.initCompleter.isCompleted) {
      MatrixState.pangeaController.initControllers();
      await MatrixState.pangeaController.getAnalytics.initCompleter.future;
    }
  }

  Future<void> _startSession() async {
    await _waitForAnalytics();
    await sessionLoader.load();
    _loadActivity();
  }

  Future<void> continueSession() async {
    if (!sessionLoader.isLoaded) return;
    sessionLoader.value!.incrementGroup();
    await VocabPracticeSessionRepo.updateSession(sessionLoader.value!);

    _loadActivity();
  }

  Future<void> completeActivitySession() async {
    if (!sessionLoader.isLoaded) return;
    final uses = sessionLoader.value!.completedUses;
    MatrixState.pangeaController.putAnalytics.addAnalytics(uses);

    sessionLoader.value!.finishSession();
    await VocabPracticeSessionRepo.updateSession(sessionLoader.value!);

    setState(() {});
  }

  Future<List<InlineSpan>?> getExampleMessage(
    ConstructIdentifier construct,
  ) async {
    for (final use in construct.constructUses.uses) {
      if (use.metadata.eventId == null || use.metadata.roomId == null) {
        continue;
      }

      final room = MatrixState.pangeaController.matrixState.client
          .getRoomById(use.metadata.roomId!);
      if (room == null) continue;

      final event = await room.getEventById(use.metadata.eventId!);
      if (event == null) continue;

      final timeline = await room.getTimeline();
      final pangeaMessageEvent = PangeaMessageEvent(
        event: event,
        timeline: timeline,
        ownMessage: event.senderId ==
            MatrixState.pangeaController.matrixState.client.userID,
      );

      final tokens = pangeaMessageEvent.messageDisplayRepresentation?.tokens;
      if (tokens == null || tokens.isEmpty) continue;
      final token = tokens.firstWhereOrNull(
        (token) => token.text.content == use.form,
      );
      if (token == null) continue;

      final text = pangeaMessageEvent.messageDisplayText;
      final tokenText = token.text.content;
      int tokenIndex = text.indexOf(tokenText);
      if (tokenIndex == -1) continue;

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

    return null;
  }

  Future<void> _loadActivity() async {
    if (!sessionLoader.isLoaded) {
      try {
        await sessionLoader.completer.future;
      } catch (_) {
        return;
      }
    }

    if (!mounted) return;

    setState(() {
      currentActivity = null;
      isLoadingActivity = true;
      activityError = null;
    });

    final session = sessionLoader.value!;
    final activityRequest = session.currentActivityRequest;
    if (activityRequest == null) {
      setState(() {
        activityError = "No current activity request.";
        isLoadingActivity = false;
      });
      return;
    }

    final result = await PracticeRepo.getPracticeActivity(activityRequest);
    result.isError
        ? activityError = result.error.toString()
        : currentActivity = result.result!;

    if (mounted) setState(() => isLoadingActivity = false);
  }

  Future<void> onSelectChoice(String choice) async {
    if (currentActivity == null) return;
    final activity = currentActivity!;
    final correct = activity.onMultipleChoiceSelect(choice);
    if (!correct) return;

    // display the fact that the choice was correct before loading the next activity
    await Future.delayed(const Duration(milliseconds: 300));

    sessionLoader.value!.completeActivity(activity);
    await VocabPracticeSessionRepo.updateSession(sessionLoader.value!);

    await _loadActivity();
  }

  @override
  Widget build(BuildContext context) => VocabPracticeView(this);
}
