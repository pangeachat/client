import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/constructs_model.dart';
import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/quests/quests_client_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_model.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/analytics_practice_session_repo.dart';
import 'package:fluffychat/routes/analytics/construct_analytics/practice/practice_session_xp.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_generation_repo.dart';
import 'package:fluffychat/routes/chat/toolbar/practice_exercises/practice_target.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _PracticeQueueEntry {
  final MessagePracticeExerciseRequest request;
  final Completer<MultipleChoicePracticeExerciseModel?> completer;

  _PracticeQueueEntry({required this.request, required this.completer});
}

class PracticeSessionController {
  PracticeSessionController();

  AnalyticsPracticeSessionModel? session;
  bool isLoadingSession = false;
  Object? sessionError;

  final Queue<_PracticeQueueEntry> _queue = Queue();

  void clear() {
    _queue.clear();
  }

  List<MessagePracticeExerciseRequest> get exerciseRequests =>
      session?.exerciseRequests ?? [];

  List<OneConstructUse> get bonusUses => session?.state.bonusUses ?? [];

  int get hintsUsed => session?.state.hintsUsed ?? 0;

  double get progress => session?.progress ?? 0;

  String getCompletionMessage(BuildContext context) =>
      session?.getCompletionMessage(context) ??
      L10n.of(context).youveCompletedPractice;

  void updateElapsedTime(int seconds) {
    session?.setElapsedSeconds(seconds);
  }

  void updateHintsPressed() {
    session?.useHint();
  }

  void updateElapsedSeconds(int seconds) {
    session?.setElapsedSeconds(seconds);
  }

  void completeExercise() {
    session?.completeExercise();
  }

  void skipExercise() {
    session?.incrementSkippedActivities();
  }

  void submitAnswer(List<OneConstructUse> uses) {
    session?.submitAnswer(uses);
  }

  Future<void> startSession(ConstructTypeEnum type, {String? missionId}) async {
    try {
      isLoadingSession = true;
      sessionError = null;
      session = null;
      earnedXp = null;

      final l1 = MatrixState.pangeaController.userController.userL1;
      final l2 = MatrixState.pangeaController.userController.userL2;
      if (l1 == null || l2 == null) throw Exception('Languages not set');
      session = await AnalyticsPracticeSessionRepo.get(
        type,
        l1,
        l2,
        missionId: missionId,
      );
    } catch (e, s) {
      if (e is! UnsubscribedException && e is! InsufficientDataException) {
        ErrorHandler.logError(e: e, s: s, data: {});
      }
      sessionError = e;
    } finally {
      isLoadingSession = false;
    }
  }

  Future<void> completeSession() async {
    session?.finishSession();
  }

  /// What the finished session's XP did; null until [measureEarnedXp] runs.
  Future<PracticeSessionXp>? earnedXp;

  /// Reads back what the finished session earned. Call once every use it
  /// recorded, bonuses included, has been written to [analytics].
  void measureEarnedXp(AnalyticsDataService analytics, String language) {
    final session = this.session;
    if (session == null) return;
    earnedXp = _measureEarnedXp(analytics, language, session);
  }

  Future<PracticeSessionXp> _measureEarnedXp(
    AnalyticsDataService analytics,
    String language,
    AnalyticsPracticeSessionModel session,
  ) async {
    try {
      final missionId = session.missionId;
      // A Mission no joined course carries any more (one since left) has no
      // meter to have moved, so it gets no Mission line.
      final mission = missionId == null
          ? null
          : await MatrixState.pangeaController.matrixState.client
                .joinedMissionGroup(missionId);
      return PracticeSessionXp.measure(
        sessionUses: session.state.recordedUses,
        learnerUses: await analytics.getUses(language),
        missionLemmas: mission?.creditedLemmas,
      );
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {'language': language, 'missionId': session.missionId},
      );
      rethrow;
    }
  }

  Future<MultipleChoicePracticeExerciseModel?> _initExerciseData(
    Future Function(PracticeTarget) onSkip,
    Future Function(MultipleChoicePracticeExerciseModel) onFetch,
  ) async {
    final requests = exerciseRequests;
    for (var i = 0; i < requests.length; i++) {
      try {
        final req = requests[i];
        final res = await _fetchExercise(req, onFetch);
        _fillExerciseQueue(requests.skip(i + 1).toList(), onSkip, onFetch);
        return res;
      } catch (e) {
        await onSkip(requests[i].target);
        // Try next request
        continue;
      }
    }
    return null;
  }

  Future<void> _fillExerciseQueue(
    List<MessagePracticeExerciseRequest> requests,
    Future Function(PracticeTarget) onSkip,
    Future Function(MultipleChoicePracticeExerciseModel) onFetch,
  ) async {
    for (final request in requests) {
      final completer = Completer<MultipleChoicePracticeExerciseModel?>();
      _queue.add(_PracticeQueueEntry(request: request, completer: completer));
      _fetchExercise(request, onFetch)
          .then((exercise) {
            exercise != null
                ? completer.complete(exercise)
                : completer.complete(null);
          })
          .catchError((e, s) async {
            completer.complete(null);
            await onSkip(request.target);
            return null;
          });
    }
  }

  Future<MultipleChoicePracticeExerciseModel?> _fetchExercise(
    MessagePracticeExerciseRequest req,
    Future Function(MultipleChoicePracticeExerciseModel) onFetch,
  ) async {
    final result = await PracticeRepo.getPracticeExercise(req, messageInfo: {});

    if (result.isError ||
        result.result is! MultipleChoicePracticeExerciseModel) {
      throw result.error ?? Exception("Failed to fetch exercise");
    }

    final exerciseModel = result.result as MultipleChoicePracticeExerciseModel;
    await onFetch(exerciseModel);
    return exerciseModel;
  }

  Future<MultipleChoicePracticeExerciseModel?> getNextExercise(
    Future Function(PracticeTarget) onSkip,
    Future Function(MultipleChoicePracticeExerciseModel) onFetch,
  ) async {
    final session = this.session;
    if (session == null) {
      throw Exception("Called getNextExercise without loading session");
    }

    if (!session.isComplete && _queue.isEmpty) {
      final initialExercise = await _initExerciseData(onSkip, onFetch);
      if (initialExercise == null && session.state.currentIndex == 0) {
        // No activities were successfully loaded, and we haven't completed any yet, so throw an error
        throw InsufficientDataException(offline: session.offline);
      }
      return initialExercise;
    }

    while (_queue.isNotEmpty) {
      final nextExerciseCompleter = _queue.removeFirst();

      try {
        final exercise = await nextExerciseCompleter.completer.future;
        if (exercise != null) {
          return exercise;
        }
      } catch (e) {
        // Completer failed, skip to next
        continue;
      }
    }

    if (session.state.currentIndex == 0) {
      // No activities were successfully loaded, and we haven't completed any yet, so throw an error
      throw InsufficientDataException(offline: session.offline);
    }

    return null;
  }
}
