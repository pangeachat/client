import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';

import 'package:fluffychat/pangea/choreographer/it/gold_route_tracker_model.dart';
import 'package:fluffychat/pangea/choreographer/it/it_repo.dart';
import 'package:fluffychat/pangea/choreographer/it/it_response_model.dart';
import 'package:fluffychat/pangea/choreographer/it/it_step_model.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'completed_it_step_model.dart';
import 'it_request_model.dart';

class ITController {
  final Function(Object) onError;

  final Queue<Completer<ITStepModel>> _queue = Queue();
  GoldRouteTrackerModel? _goldRouteTracker;

  final ValueNotifier<String?> _sourceText = ValueNotifier(null);
  final ValueNotifier<ITStepModel?> _currentITStep = ValueNotifier(null);
  final ValueNotifier<bool> _open = ValueNotifier(false);
  final ValueNotifier<bool> _editing = ValueNotifier(false);

  ITController(this.onError);

  ValueNotifier<bool> get open => _open;
  ValueNotifier<bool> get editing => _editing;
  ValueNotifier<ITStepModel?> get currentITStep => _currentITStep;
  ValueNotifier<String?> get sourceText => _sourceText;
  StreamController<CompletedITStepModel> acceptedContinuanceStream =
      StreamController.broadcast();

  bool _continuing = false;
  bool dismissed = false;

  ITRequestModel _request(String textInput) {
    assert(_sourceText.value != null);
    return ITRequestModel(
      text: _sourceText.value!,
      customInput: textInput,
      sourceLangCode: MatrixState.pangeaController.userController.userL1Code!,
      targetLangCode: MatrixState.pangeaController.userController.userL2Code!,
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

  void clearSourceText() {
    _sourceText.value = null;
  }

  void clearDissmissed() {
    dismissed = false;
  }

  void dispose() {
    acceptedContinuanceStream.close();
    _open.dispose();
    _editing.dispose();
    _currentITStep.dispose();
    _sourceText.dispose();
  }

  void openIT(String text) {
    _sourceText.value = text;
    _open.value = true;
    _continueIT();
  }

  void closeIT({bool dismiss = false}) {
    MatrixState.pAnyState.closeOverlay("it_feedback_card");

    setEditingSourceText(false);
    if (dismiss) {
      dismissed = true;
    }

    _open.value = false;
    _queue.clear();
    _currentITStep.value = null;
    _goldRouteTracker = null;
  }

  void setEditingSourceText(bool value) {
    _editing.value = value;
  }

  void submitSourceTextEdits(String text) {
    _queue.clear();
    _currentITStep.value = null;
    _goldRouteTracker = null;
    _sourceText.value = text;
    setEditingSourceText(false);
    _continueIT();
  }

  ContinuanceModel selectContinuance(int index) {
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

  void acceptContinuance(int chosenIndex) {
    if (_currentITStep.value == null) {
      throw "onAcceptContinuance called when _currentITStep is null";
    }

    if (chosenIndex < 0 ||
        chosenIndex >= _currentITStep.value!.continuances.length) {
      throw "onAcceptContinuance called with invalid index $chosenIndex";
    }

    acceptedContinuanceStream.add(
      CompletedITStepModel(
        _currentITStep.value!.continuances,
        chosen: chosenIndex,
      ),
    );
    _continueIT();
  }

  Future<void> _continueIT() async {
    if (_continuing) return;
    _continuing = true;

    try {
      if (_currentITStep.value == null) {
        await _initTranslationData();
      } else if (_queue.isEmpty) {
        closeIT();
      } else {
        final nextStepCompleter = _queue.removeFirst();
        _currentITStep.value = await nextStepCompleter.future;
      }
    } catch (e) {
      onError(e);
    } finally {
      _continuing = false;
    }
  }

  Future<void> _initTranslationData() async {
    final res = await _safeRequest("");
    if (_sourceText.value == null || !_open.value) return;
    if (res.isError || res.result?.goldContinuances == null) {
      onError(res.asError!);
      return;
    }

    final result = res.result!;
    _goldRouteTracker = GoldRouteTrackerModel(
      result.goldContinuances!,
      _sourceText.value!,
    );

    _currentITStep.value = ITStepModel.fromResponse(
      sourceText: _sourceText.value!,
      currentText: "",
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
      if (_sourceText.value == null || !_open.value) {
        return;
      }

      final completer = Completer<ITStepModel>();
      _queue.add(completer);
      final resp = await _safeRequest(currentText);
      if (resp.isError) {
        completer.completeError(resp.asError!);
        break;
      } else {
        final step = ITStepModel.fromResponse(
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
