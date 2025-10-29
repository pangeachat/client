import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:async/async.dart';

import 'package:fluffychat/pangea/choreographer/constants/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/controllers/error_service.dart';
import 'package:fluffychat/pangea/choreographer/enums/choreo_mode.dart';
import 'package:fluffychat/pangea/choreographer/enums/edit_type.dart';
import 'package:fluffychat/pangea/choreographer/repo/it_repo.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import '../models/it_step.dart';
import '../repo/it_request_model.dart';
import '../repo/it_response_model.dart';
import 'choreographer.dart';

class ITController {
  final Choreographer _choreographer;

  ITStep? _currentITStep;
  final List<Completer<ITStep>> _queue = [];
  GoldRouteTracker? _goldRouteTracker;

  bool _open = false;
  bool _editing = false;
  bool _dismissed = false;

  ITController(this._choreographer);

  bool get open => _open;
  bool get editing => _editing;
  bool get dismissed => _dismissed;
  List<Continuance>? get continuances => _currentITStep?.continuances;
  bool get isTranslationDone => _currentITStep?.isFinal ?? false;

  String? get _sourceText => _choreographer.sourceText;

  ITRequestModel _request(String textInput) {
    assert(_sourceText != null);
    return ITRequestModel(
      text: _sourceText!,
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

  void openIT() => _open = true;

  void closeIT() {
    // if the user hasn't gone through any IT steps, reset the text
    if (_choreographer.currentText.isEmpty && _sourceText != null) {
      _choreographer.textController.setSystemText(
        _sourceText!,
        EditType.itDismissed,
      );
    }

    clear(dismissed: true);
  }

  void clear({bool dismissed = false}) {
    MatrixState.pAnyState.closeOverlay("it_feedback_card");

    _open = false;
    _editing = false;
    _dismissed = dismissed;
    _queue.clear();
    _currentITStep = null;
    _goldRouteTracker = null;

    _choreographer.setChoreoMode(ChoreoMode.igc);
    _choreographer.setSourceText(null);
  }

  void setEditing(bool value) => _editing = value;

  void onSubmitEdits() {
    _editing = false;
    _queue.clear();
    _currentITStep = null;
    _goldRouteTracker = null;
    continueIT();
  }

  Continuance onSelectContinuance(int index) {
    if (_currentITStep == null) {
      throw "onSelectContinuance called with null currentITStep";
    }

    if (index < 0 || index >= _currentITStep!.continuances.length) {
      throw "onSelectContinuance called with invalid index $index";
    }

    final step = _currentITStep!.continuances[index];
    _currentITStep!.continuances[index] = step.copyWith(
      wasClicked: true,
    );
    return _currentITStep!.continuances[index];
  }

  CompletedITStep getAcceptedITStep(int chosenIndex) {
    if (_currentITStep == null) {
      throw "getAcceptedITStep called with null currentITStep";
    }

    if (chosenIndex < 0 || chosenIndex >= _currentITStep!.continuances.length) {
      throw "getAcceptedITStep called with invalid index $chosenIndex";
    }

    return CompletedITStep(
      _currentITStep!.continuances,
      chosen: chosenIndex,
    );
  }

  Future<void> continueIT() async {
    if (_currentITStep == null) {
      await _initTranslationData();
      return;
    }

    if (_queue.isEmpty) {
      _choreographer.closeIT();
      return;
    }

    final nextStepCompleter = _queue.removeAt(0);
    try {
      _currentITStep = await nextStepCompleter.future;
    } catch (e) {
      if (_open) {
        _choreographer.errorService.setErrorAndLock(
          ChoreoError(raw: e),
        );
      }
    }
  }

  Future<void> _initTranslationData() async {
    final String currentText = _choreographer.currentText;
    final res = await ITRepo.get(_request(currentText)).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        return Result.error(
          TimeoutException("ITRepo.get timed out after 10 seconds"),
        );
      },
    );

    if (_sourceText == null || !_open) return;
    if (res.isError || res.result?.goldContinuances == null) {
      _choreographer.errorService.setErrorAndLock(
        ChoreoError(raw: res.asError),
      );
      return;
    }

    final result = res.result!;
    _goldRouteTracker = GoldRouteTracker(
      result.goldContinuances!,
      _sourceText!,
    );

    _currentITStep = ITStep(
      sourceText: _sourceText!,
      currentText: currentText,
      responseModel: res.result!,
      storedGoldContinuances: _goldRouteTracker!.continuances,
    );

    _fillITStepQueue();
  }

  Future<void> _fillITStepQueue() async {
    if (_sourceText == null || _goldRouteTracker!.continuances.length < 2) {
      return;
    }

    final sourceText = _sourceText!;
    String currentText =
        _choreographer.currentText + _goldRouteTracker!.continuances[0].text;

    for (int i = 1; i < _goldRouteTracker!.continuances.length; i++) {
      _queue.add(Completer<ITStep>());
      final res = await ITRepo.get(_request(currentText)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          return Result.error(
            TimeoutException("ITRepo.get timed out after 10 seconds"),
          );
        },
      );

      if (res.isError) {
        _queue.last.completeError(res.asError!);
        break;
      } else {
        final step = ITStep(
          sourceText: sourceText,
          currentText: currentText,
          responseModel: res.result!,
          storedGoldContinuances: _goldRouteTracker!.continuances,
        );
        _queue.last.complete(step);
      }

      currentText += _goldRouteTracker!.continuances[i].text;
    }
  }
}

class GoldRouteTracker {
  final String _originalText;
  final List<Continuance> continuances;

  const GoldRouteTracker(this.continuances, String originalText)
      : _originalText = originalText;

  Continuance? currentContinuance({
    required String currentText,
    required String sourceText,
  }) {
    if (_originalText != sourceText) {
      debugPrint("$_originalText != $_originalText");
      return null;
    }

    String stack = "";
    for (final cont in continuances) {
      if (stack == currentText) {
        return cont;
      }
      stack += cont.text;
    }

    return null;
  }

  String? get fullTranslation {
    if (continuances.isEmpty) return null;
    String full = "";
    for (final cont in continuances) {
      full += cont.text;
    }
    return full;
  }
}

class ITStep {
  late List<Continuance> continuances;
  late bool isFinal;

  ITStep({
    required String sourceText,
    required String currentText,
    required ITResponseModel responseModel,
    required List<Continuance>? storedGoldContinuances,
  }) {
    final List<Continuance> gold =
        storedGoldContinuances ?? responseModel.goldContinuances ?? [];
    final goldTracker = GoldRouteTracker(gold, sourceText);

    isFinal = responseModel.isFinal;

    if (responseModel.continuances.isEmpty) {
      continuances = [];
    } else {
      final Continuance? goldCont = goldTracker.currentContinuance(
        currentText: currentText,
        sourceText: sourceText,
      );
      if (goldCont != null) {
        continuances = [
          ...responseModel.continuances
              .where((c) => c.text.toLowerCase() != goldCont.text.toLowerCase())
              .map((e) {
            //we only want one green choice and for that to be our gold
            if (e.level == ChoreoConstants.levelThresholdForGreen) {
              return e.copyWith(
                level: ChoreoConstants.levelThresholdForYellow,
              );
            }
            return e;
          }),
          goldCont,
        ];
        continuances.shuffle();
      } else {
        continuances = List<Continuance>.from(responseModel.continuances);
      }
    }
  }
}
