import 'package:fluffychat/pangea/choreographer/constants/choreo_constants.dart';
import 'package:fluffychat/pangea/choreographer/models/completed_it_step.dart';
import 'package:fluffychat/pangea/choreographer/models/gold_route_tracker.dart';
import 'package:fluffychat/pangea/choreographer/repo/it_response_model.dart';

class ITStep {
  late List<Continuance> continuances;
  late bool isFinal;

  ITStep({this.continuances = const [], this.isFinal = false});

  factory ITStep.fromResponse({
    required String sourceText,
    required String currentText,
    required ITResponseModel responseModel,
    required List<Continuance>? storedGoldContinuances,
  }) {
    final List<Continuance> gold =
        storedGoldContinuances ?? responseModel.goldContinuances ?? [];
    final goldTracker = GoldRouteTracker(gold, sourceText);

    final isFinal = responseModel.isFinal;
    List<Continuance> continuances;
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

    return ITStep(
      continuances: continuances,
      isFinal: isFinal,
    );
  }

  ITStep copyWith({
    List<Continuance>? continuances,
    bool? isFinal,
  }) {
    return ITStep(
      continuances: continuances ?? this.continuances,
      isFinal: isFinal ?? this.isFinal,
    );
  }
}
