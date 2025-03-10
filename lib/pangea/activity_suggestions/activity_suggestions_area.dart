// shows n rows of activity suggestions vertically, where n is the number of rows
// as the user tries to scroll horizontally to the right, the client will fetch more activity suggestions

import 'dart:math';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:fluffychat/pages/settings_style/settings_style.dart';
import 'package:fluffychat/pangea/activity_planner/activity_mode_list_repo.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_request.dart';
import 'package:fluffychat/pangea/activity_planner/learning_objective_list_repo.dart';
import 'package:fluffychat/pangea/activity_planner/list_request_schema.dart';
import 'package:fluffychat/pangea/activity_planner/media_enum.dart';
import 'package:fluffychat/pangea/activity_planner/topic_list_repo.dart';
import 'package:fluffychat/pangea/learning_settings/constants/language_constants.dart';
import 'package:fluffychat/pangea/learning_settings/enums/language_level_type_enum.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';

class ActivitySuggestionsArea extends StatefulWidget {
  const ActivitySuggestionsArea({super.key});

  @override
  ActivitySuggestionsAreaState createState() => ActivitySuggestionsAreaState();
}

class ActivitySuggestionsAreaState extends State<ActivitySuggestionsArea> {
  @override
  void initState() {
    super.initState();
    _setActivitiesList();
  }

  ActivitySettingRequestSchema get req => ActivitySettingRequestSchema(
        langCode:
            MatrixState.pangeaController.languageController.userL2?.langCode ??
                LanguageKeys.defaultLanguage,
      );

  List<ActivitySettingResponseSchema> _topicItems = [];
  List<ActivitySettingResponseSchema> _modeItems = [];
  List<ActivitySettingResponseSchema> _objectiveItems = [];

  Future<void> _setActivitiesList() async {
    _topicItems = await TopicListRepo.get(req);
    _modeItems = await ActivityModeListRepo.get(req);
    _objectiveItems = await LearningObjectiveListRepo.get(req);
    if (mounted) setState(() {});
  }

  List<ActivityPlanModel> get _activityItems {
    int numActivities = min(_topicItems.length, _modeItems.length);
    numActivities = min(numActivities, _objectiveItems.length);
    return List.generate(numActivities, (index) {
      return ActivityPlanModel(
        req: ActivityPlanRequest(
          topic: _topicItems[index].name,
          mode: _modeItems[index].name,
          objective: _objectiveItems[index].name,
          media: MediaEnum.nan,
          cefrLevel: LanguageLevelTypeEnum.a1,
          languageOfInstructions: LanguageKeys.defaultLanguage,
          targetLanguage: LanguageKeys.defaultLanguage,
          numberOfParticipants: 1,
        ),
        title: _topicItems[index].name,
        learningObjective: _objectiveItems[index].name,
        instructions: _modeItems[index].name,
        vocab: [],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      // appBar: AppBar(
      //   title: Text(L10n.of(context).chat),
      //   automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
      //   centerTitle: FluffyThemes.isColumnMode(context),
      // ),
      body: MaxWidthBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DynamicColorBuilder(
              builder: (light, dark) {
                final systemColor =
                    Theme.of(context).brightness == Brightness.light
                        ? light?.primary
                        : dark?.primary;
                final colors =
                    List<Color?>.from(SettingsStyleController.customColors);
                if (systemColor == null) {
                  colors.remove(null);
                }
                return GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 64,
                  ),
                  itemCount: colors.length,
                  itemBuilder: (context, i) {
                    final color = colors[i];
                    return Container(
                      decoration: const BoxDecoration(color: Colors.green),
                      width: 50,
                      height: 50,
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
      // body: MaxWidthBody(
      //   // child: Container(
      //   //   decoration: const BoxDecoration(color: Colors.green),
      //   //   height: 50,
      //   //   width: 50,
      //   // ),
      //   child: Column(
      //     children: [
      //       Expanded(
      //         child: GridView.builder(
      //           gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      //             maxCrossAxisExtent: 128,
      //           ),
      //           itemBuilder: (context, i) {
      //             return ActivitySuggestionCard(
      //               activity: _activityItems[i],
      //             );
      //           },
      //         ),
      //       ),
      //     ],
      //   ),
      // ),
    );
    // return ListView.builder(
    //   scrollDirection: Axis.vertical,
    //   itemCount: 5,
    //   itemBuilder: (context, index) {
    //     return Container(
    //       height: 100,
    //       width: 100,
    //       color: Colors.blue,
    //       margin: const EdgeInsets.all(10),
    //     );
    //   },
    // );
  }
}
