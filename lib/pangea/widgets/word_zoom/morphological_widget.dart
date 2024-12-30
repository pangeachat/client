import 'package:fluffychat/pangea/constants/morph_categories_and_labels.dart';
import 'package:fluffychat/pangea/enum/analytics/morph_categories_enum.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';
import 'package:flutter/material.dart';

class ActivityMorph {
  final String morphFeature;
  final String morphTag;
  bool revealed;

  ActivityMorph({
    required this.morphFeature,
    required this.morphTag,
    required this.revealed,
  });
}

class MorphologicalListWidget extends StatelessWidget {
  final PangeaToken token;
  final String? selectedMorphFeature;
  final Function(String?) setMorphFeature;

  const MorphologicalListWidget({
    super.key,
    required this.selectedMorphFeature,
    required this.token,
    required this.setMorphFeature,
  });

  List<ActivityMorph> get _visibleMorphs {
    final activityMorphs = token.morph.entries.map((entry) {
      return ActivityMorph(
        morphFeature: entry.key,
        morphTag: entry.value,
        revealed: !token.shouldDoMorphActivity(entry.key),
      );
    }).toList();

    activityMorphs.sort((a, b) {
      if (a.morphFeature.toLowerCase() == "pos") {
        return -1;
      } else if (b.morphFeature.toLowerCase() == "pos") {
        return 1;
      }

      if (a.revealed && !b.revealed) {
        return -1;
      } else if (!a.revealed && b.revealed) {
        return 1;
      }

      return a.morphFeature.compareTo(b.morphFeature);
    });

    final lastRevealedIndex =
        activityMorphs.lastIndexWhere((morph) => morph.revealed);

    if (lastRevealedIndex == -1) {
      return activityMorphs;
    } else if (lastRevealedIndex >= (activityMorphs.length - 1)) {
      return activityMorphs;
    } else {
      return activityMorphs.take(lastRevealedIndex + 2).toList();
    }
    // // we always start with the part of speech
    // final visibleMorphs = [
    //   ActivityMorph(
    //     morphFeature: "pos",
    //     morphTag: token.pos,
    //     revealed: !token.shouldDoPosActivity,
    //     // revealed: !shouldDoActivity || !canGenerateDistractors,
    //   ),
    // ];

    // // each pos has a defined set of morphological features to display and do activities for
    // final List<String> seq = MorphActivityGenerator().getSequence(
    //   MatrixState.pangeaController.languageController.userL2?.langCode,
    //   token.pos,
    // );

    // for (final String feature in seq) {
    //   // don't add any more if the last one is not revealed yet
    //   if (!visibleMorphs.last.revealed) {
    //     break;
    //   }

    //   // check that the feature is in token.morph
    //   if (!token.morph.containsKey(feature)) {
    //     ErrorHandler.logError(
    //       m: "Morphological feature suggested for pos but not found in token",
    //       data: {
    //         "feature": feature,
    //         "token": token,
    //         "lang_code": MatrixState
    //             .pangeaController.languageController.userL2?.langCode,
    //       },
    //     );
    //     continue;
    //   }

    //   visibleMorphs.add(
    //     ActivityMorph(
    //       morphFeature: feature,
    //       morphTag: token.morph[feature],
    //       revealed: !token.shouldDoMorphActivity(feature),
    //     ),
    //   );
    // }

    // return visibleMorphs;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: _visibleMorphs.map((morph) {
        return Padding(
          padding: const EdgeInsets.all(2.0),
          child: MorphologicalActivityButton(
            onPressed: setMorphFeature,
            morphCategory: morph.morphFeature,
            icon: getIconForMorphFeature(morph.morphFeature),
            isUnlocked: morph.revealed,
            isSelected: selectedMorphFeature == morph.morphFeature,
          ),
        );
      }).toList(),
    );
  }
}

class MorphologicalActivityButton extends StatelessWidget {
  final Function(String) onPressed;
  final String morphCategory;
  final IconData icon;

  final bool isUnlocked;
  final bool isSelected;

  const MorphologicalActivityButton({
    required this.onPressed,
    required this.morphCategory,
    required this.icon,
    this.isUnlocked = true,
    this.isSelected = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Tooltip(
          message: getMorphologicalCategoryCopy(
            morphCategory,
            context,
          ),
          child: Opacity(
            opacity: (isSelected || !isUnlocked) ? 1 : 0.5,
            child: IconButton(
              onPressed: () => onPressed(morphCategory),
              icon: Icon(icon),
              color: isSelected ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ),
      ],
    );
  }
}
