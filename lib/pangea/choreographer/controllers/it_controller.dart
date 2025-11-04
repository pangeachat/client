import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';

import 'package:fluffychat/pangea/choreographer/controllers/error_service.dart';
import 'package:fluffychat/pangea/choreographer/enums/choreo_mode.dart';
import 'package:fluffychat/pangea/choreographer/enums/edit_type.dart';
import 'package:fluffychat/pangea/choreographer/models/gold_route_tracker.dart';
import 'package:fluffychat/pangea/choreographer/models/it_step.dart';
import 'package:fluffychat/pangea/choreographer/repo/it_repo.dart';
import 'package:fluffychat/pangea/choreographer/repo/it_response_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../models/completed_it_step.dart';
import '../repo/it_request_model.dart';
import 'choreographer.dart';

class ITController {
  final Choreographer _choreographer;

  final ValueNotifier<ITStep?> _currentITStep = ValueNotifier(null);
  final Queue<Completer<ITStep>> _queue = Queue();
  GoldRouteTracker? _goldRouteTracker;

  final ValueNotifier<bool> _open = ValueNotifier(false);
  final ValueNotifier<bool> _editing = ValueNotifier(false);
  bool _dismissed = false;

  ITController(this._choreographer);

  ValueNotifier<bool> get open => _open;
  ValueNotifier<bool> get editing => _editing;
  bool get dismissed => _dismissed;
  ValueNotifier<ITStep?> get currentITStep => _currentITStep;

  ValueNotifier<String?> get _sourceText => _choreographer.sourceText;

  ITRequestModel _request(String textInput) {
    assert(_sourceText.value != null);
    return ITRequestModel(
      text: _sourceText.value!,
      customInput: textInput,
      sourceLangCode:
          MatrixState.pangeaController.languageController.activeL1Code()!,
      targetLangCode:
          MatrixState.pangeaController.languageController.activeL2Code()!,
      userId: _choreographer.chatController.room.client.userID!,
      roomId: _choreographer.chatController.room.id,
      goldTranslation: _goldRouteTracker?.fullTranslation,
      goldContinuances: _goldRouteTracker?.continuances,
    );
  }

  Future<Result<ITResponseModel>> _safeRequest(String text) {
    return ITRepo.get(_request(text)).timeout(
      const Duration(seconds: 10),
      onTimeout: () => Result.error(
        TimeoutException("ITRepo.get timed out after 10 seconds"),
      ),
    );
  }

  void clear({bool dismissed = false}) {
    MatrixState.pAnyState.closeOverlay("it_feedback_card");

    _open.value = false;
    _editing.value = false;
    _dismissed = dismissed;
    _queue.clear();
    _currentITStep.value = null;
    _goldRouteTracker = null;

    _choreographer.setChoreoMode(ChoreoMode.igc);
    _choreographer.setSourceText(null);
  }

  void dispose() {
    _currentITStep.dispose();
    _editing.dispose();
  }

  void openIT() {
    _open.value = true;
    continueIT();
  }

  void closeIT() {
    // if the user hasn't gone through any IT steps, reset the text
    if (_choreographer.currentText.isEmpty && _sourceText.value != null) {
      _choreographer.textController.setSystemText(
        _sourceText.value!,
        EditType.itDismissed,
      );
    }

    clear(dismissed: true);
  }

  void setEditing(bool value) {
    _editing.value = value;
  }

  void onSubmitEdits() {
    _editing.value = false;
    _queue.clear();
    _currentITStep.value = null;
    _goldRouteTracker = null;
    continueIT();
  }

  Continuance onSelectContinuance(int index) {
    if (_currentITStep.value == null) {
      throw "onSelectContinuance called when _currentITStep is null";
    }

    if (index < 0 || index >= _currentITStep.value!.continuances.length) {
      throw "onSelectContinuance called with invalid index $index";
    }

    final currentStep = _currentITStep.value!;
    currentStep.continuances[index] = currentStep.continuances[index].copyWith(
      wasClicked: true,
    );
    _currentITStep.value = _currentITStep.value!.copyWith(
      continuances: currentStep.continuances,
    );
    return _currentITStep.value!.continuances[index];
  }

  CompletedITStep onAcceptContinuance(int chosenIndex) {
    if (_currentITStep.value == null) {
      throw "onAcceptContinuance called when _currentITStep is null";
    }

    if (chosenIndex < 0 ||
        chosenIndex >= _currentITStep.value!.continuances.length) {
      throw "onAcceptContinuance called with invalid index $chosenIndex";
    }

    final completedStep = CompletedITStep(
      _currentITStep.value!.continuances,
      chosen: chosenIndex,
    );

    continueIT();
    return completedStep;
  }

  bool _continuing = false;
  Future<void> continueIT() async {
    if (_continuing) return;
    _continuing = true;

    try {
      if (_currentITStep.value == null) {
        await _initTranslationData();
      } else if (_queue.isEmpty) {
        _choreographer.closeIT();
      } else {
        final nextStepCompleter = _queue.removeFirst();
        _currentITStep.value = await nextStepCompleter.future;
      }
    } catch (e) {
      _choreographer.errorService.setErrorAndLock(ChoreoError(raw: e));
    } finally {
      _continuing = false;
    }
  }

  Future<void> _initTranslationData() async {
    final String currentText = _choreographer.currentText;
    final res = await _safeRequest(currentText);
    if (_sourceText.value == null || !_open.value) return;
    if (res.isError || res.result?.goldContinuances == null) {
      _choreographer.errorService.setErrorAndLock(
        ChoreoError(raw: res.asError),
      );
      return;
    }

    final result = res.result!;
    _goldRouteTracker = GoldRouteTracker(
      result.goldContinuances!,
      _sourceText.value!,
    );

    _currentITStep.value = ITStep.fromResponse(
      sourceText: _sourceText.value!,
      currentText: currentText,
      responseModel: res.result!,
      storedGoldContinuances: _goldRouteTracker!.continuances,
    );

    _fillITStepQueue();
  }

  Future<void> _fillITStepQueue() async {
    if (_sourceText.value == null ||
        _goldRouteTracker!.continuances.length < 2) {
      return;
    }

    final sourceText = _sourceText.value!;
    final goldContinuances = _goldRouteTracker!.continuances;
    String currentText = goldContinuances[0].text;
    for (int i = 1; i < goldContinuances.length; i++) {
      final completer = Completer<ITStep>();
      _queue.add(completer);
      final resp = await _safeRequest(currentText);
      if (resp.isError) {
        completer.completeError(resp.asError!);
        break;
      } else {
        final step = ITStep.fromResponse(
          sourceText: sourceText,
          currentText: currentText,
          responseModel: resp.result!,
          storedGoldContinuances: goldContinuances,
        );
        completer.complete(step);
      }

      currentText += goldContinuances[i].text;
    }
  }
}
