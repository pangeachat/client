import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/morphs/default_morph_mapping.dart';
import 'package:fluffychat/pangea/morphs/morph_models.dart';
import 'package:fluffychat/pangea/morphs/morph_repo.dart';
import 'package:fluffychat/pangea/practice_activities/message_activity_request.dart';
import 'package:fluffychat/pangea/practice_activities/multiple_choice_activity_model.dart';
import 'package:fluffychat/pangea/practice_activities/practice_activity_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class MorphCategoryActivityGenerator {
  static Future<MessageActivityResponse> get(
    MessageActivityRequest req,
  ) async {
    if (req.targetMorphFeature == null) {
      throw ArgumentError(
        "MorphCategoryActivityGenerator requires a targetMorphFeature",
      );
    }

    final feature = req.targetMorphFeature!;
    final morphTag = req.targetTokens.first.getMorphTag(feature);
    if (morphTag == null) {
      throw ArgumentError(
        "Token does not have the specified morph feature",
      );
    }

    MorphFeaturesAndTags morphs = defaultMorphMapping;

    try {
      final resp = await MorphsRepo.get();
      morphs = resp;
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"l2": MatrixState.pangeaController.userController.userL2},
      );
    }

    final List<String> allTags = morphs.getDisplayTags(feature.name);
    final List<String> possibleDistractors = allTags
        .where(
          (tag) => tag.toLowerCase() != morphTag.toLowerCase() && tag != "X",
        )
        .toList();

    possibleDistractors.shuffle();
    final choices = possibleDistractors.take(3).toSet();
    choices.add(morphTag);

    return MessageActivityResponse(
      activity: PracticeActivityModel(
        activityType: req.targetType,
        targetTokens: [req.targetTokens.first],
        langCode: req.userL2,
        morphFeature: feature,
        multipleChoiceContent: MultipleChoiceActivity(
          choices: choices,
          answers: {morphTag},
        ),
      ),
    );
  }
}
