import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/constructs_model.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_repo.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/practice_exercises/message_practice_exercise_request.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_exercise_model.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_generation_repo.dart';
import 'package:fluffychat/pangea/practice_exercises/practice_target.dart';
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

  List<OneConstructUse> get bonusUses => session?.state.allBonusUses ?? [];

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

  Future<void> startSession(ConstructTypeEnum type) async {
    try {
      isLoadingSession = true;
      sessionError = null;
      session = null;

      final l2 =
          MatrixState.pangeaController.userController.userL2?.langCodeShort;
      if (l2 == null) throw Exception('User L2 language not set');
      session = await AnalyticsPracticeSessionRepo.get(type, l2);
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
        throw InsufficientDataException();
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
      throw InsufficientDataException();
    }

    return null;
  }
}
