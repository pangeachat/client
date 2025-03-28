import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/pangea/activity_planner/activity_planner_page.dart';
import 'package:fluffychat/pangea/activity_planner/bookmarked_activities_repo.dart';
import 'package:fluffychat/pangea/activity_suggestions/activity_suggestion_card.dart';
import 'package:fluffychat/pangea/activity_suggestions/activity_suggestion_dialog.dart';

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

  final double cardHeight = 250.0;
  double get cardPadding => _isColumnMode ? 8.0 : 0.0;
  double get cardWidth => _isColumnMode ? 225.0 : 150.0;

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
                      return ActivitySuggestionDialog(
                        activity: activity,
                        buttonText: L10n.of(context).inviteAndLaunch,
                        room: widget.room,
                      );
                    },
                  );
                },
                width: cardWidth,
                height: cardHeight,
                padding: cardPadding,
                onChange: () => setState(() {}),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
