import 'package:fluffychat/pangea/choreographer/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/it/completed_it_step_model.dart';
import 'package:fluffychat/pangea/choreographer/it/gold_route_tracker_model.dart';
import 'package:fluffychat/pangea/choreographer/it/it_response_model.dart';

class ITStepModel {
  late List<ContinuanceModel> continuances;
  late bool isFinal;

  ITStepModel({this.continuances = const [], this.isFinal = false});

  factory ITStepModel.fromResponse({
    required String sourceText,
    required String currentText,
    required ITResponseModel responseModel,
    required List<ContinuanceModel>? storedGoldContinuances,
  }) {
    final List<ContinuanceModel> gold =
        storedGoldContinuances ?? responseModel.goldContinuances ?? [];
    final goldTracker = GoldRouteTrackerModel(gold, sourceText);

    final isFinal = responseModel.isFinal;
    List<ContinuanceModel> continuances;
    if (responseModel.continuances.isEmpty) {
      continuances = [];
    } else {
      final ContinuanceModel? goldCont = goldTracker.currentContinuance(
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
        continuances = List<ContinuanceModel>.from(responseModel.continuances);
      }
    }

    return ITStepModel(
      continuances: continuances,
      isFinal: isFinal,
    );
  }

  ITStepModel copyWith({
    List<ContinuanceModel>? continuances,
    bool? isFinal,
  }) {
    return ITStepModel(
      continuances: continuances ?? this.continuances,
      isFinal: isFinal ?? this.isFinal,
    );
  }
}
