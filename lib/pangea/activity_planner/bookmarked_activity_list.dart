import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_planner/activity_planner_builder.dart';
import 'package:fluffychat/pangea/activity_planner/activity_planner_page.dart';
import 'package:fluffychat/pangea/activity_planner/bookmarked_activities_repo.dart';
import 'package:fluffychat/pangea/activity_suggestions/activity_suggestion_card.dart';
import 'package:fluffychat/pangea/activity_suggestions/activity_suggestion_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

class BookmarkedActivitiesList extends StatefulWidget {
  final Room? room;

  final ActivityPlannerPageState controller;

  const BookmarkedActivitiesList({
    super.key,
    required this.room,
    required this.controller,
  });

  @override
  BookmarkedActivitiesListState createState() =>
      BookmarkedActivitiesListState();
}

class BookmarkedActivitiesListState extends State<BookmarkedActivitiesList> {
  List<ActivityPlanModel> get _bookmarkedActivities =>
      BookmarkedActivitiesRepo.get();

  bool get _isColumnMode => FluffyThemes.isColumnMode(context);

  double get cardHeight => _isColumnMode ? 325.0 : 250.0;
  double get cardWidth => _isColumnMode ? 225.0 : 150.0;

  Future<void> _onEdit(
    String activityId,
    ActivityPlanModel activity,
    Uint8List? avatar,
    String? filename,
  ) async {
    if (avatar != null) {
      final url = await Matrix.of(context).client.uploadContent(
            avatar,
            filename: filename,
          );
      if (!mounted) return;
      setState(() {
        activity = ActivityPlanModel(
          req: activity.req,
          title: activity.title,
          learningObjective: activity.learningObjective,
          instructions: activity.instructions,
          vocab: activity.vocab,
          imageURL: url.toString(),
        );
      });
    }

    await BookmarkedActivitiesRepo.remove(activityId);
    await BookmarkedActivitiesRepo.save(activity);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    if (_bookmarkedActivities.isEmpty) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            l10n.noBookmarkedActivities,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Expanded(
      child: SingleChildScrollView(
        child: SizedBox(
          width: 800.0,
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            runSpacing: 16.0,
            spacing: 4.0,
            children: _bookmarkedActivities.map((activity) {
              return ActivitySuggestionCard(
                activity: activity,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return ActivityPlannerBuilder(
                        initialActivity: activity,
                        onEdit: _onEdit,
                        room: widget.room,
                        builder: (controller) {
                          return ActivitySuggestionDialog(
                            controller: controller,
                            buttonText: l10n.launch,
                          );
                        },
                      );
                    },
                  );
                },
                width: cardWidth,
                height: cardHeight,
                onChange: () => setState(() {}),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
