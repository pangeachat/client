import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_model.dart';
import 'package:fluffychat/pangea/analytics_practice/analytics_practice_session_repo.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:matrix/matrix.dart';

class SessionLoader extends AsyncLoader<AnalyticsPracticeSessionModel> {
  final ConstructTypeEnum type;
  SessionLoader({required this.type});

  @override
  Future<AnalyticsPracticeSessionModel> fetch() {
    final l2 =
        MatrixState.pangeaController.userController.userL2?.langCodeShort;
    if (l2 == null) throw Exception('User L2 language not set');
    return AnalyticsPracticeSessionRepo.get(type, l2);
  }
}

class PracticeSessionController {
  final ConstructTypeEnum type;
  late final SessionLoader _loader;

  PracticeSessionController({required this.type}) {
    _loader = SessionLoader(type: type);
  }

  void dispose() {
    _loader.dispose();
  }

  void updateElapsedTime(int seconds) {
    if (_loader.value == null) {
      Logs().w('Attempted to update elapsed time before session was loaded');
      return;
    }

    _loader.value!.setElapsedSeconds(seconds);
  }

  void updateHintsPressed() {
    if (_loader.value == null) {
      Logs().w('Attempted to use hint before session was loaded');
      return;
    }

    _loader.value!.useHint();
  }

  Future<void> startSession() async {
    // await _waitForAnalytics();
    await _loader.load();
    // if (_loader.isError) {
    //   AnalyticsPractice.bypassExitConfirmation = true;
    //   return;
    // }

    // progressNotifier.value = _sessionLoader.value!.progress;
    // await _continueSession();
  }

  Future<void> reloadSession() async {
    // _clearState();
    _loader.reset();
    await startSession();
  }

  Future<void> completeSession() async {
    _loader.value!.finishSession();
    // setState(() {});

    // final bonus = _sessionLoader.value!.state.allBonusUses;
    // await _analyticsService.updateService.addAnalytics(
    //   null,
    //   bonus,
    //   _l2!.langCodeShort,
    //   forceUpdate: true,
    // );
    // AnalyticsPractice.bypassExitConfirmation = true;
  }
}
