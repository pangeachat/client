import 'dart:async';

import 'package:fluffychat/pangea/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/enum/bar_chart_view_enum.dart';
import 'package:fluffychat/pangea/enum/construct_type_enum.dart';
import 'package:fluffychat/pangea/extensions/client_extension/client_extension.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:fluffychat/pangea/models/analytics/chart_analytics_model.dart';
import 'package:fluffychat/pangea/models/language_model.dart';
import 'package:fluffychat/pangea/pages/analytics/analytics_language_button.dart';
import 'package:fluffychat/pangea/pages/analytics/analytics_view_button.dart';
import 'package:fluffychat/pangea/pages/analytics/base_analytics.dart';
import 'package:fluffychat/pangea/pages/analytics/construct_list.dart';
import 'package:fluffychat/pangea/pages/analytics/messages_bar_chart.dart';
import 'package:fluffychat/pangea/pages/analytics/time_span_menu_button.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

class RoomDetailsAnalytics extends StatefulWidget {
  final Room room;
  final BarChartViewSelection initialView;
  const RoomDetailsAnalytics({
    super.key,
    required this.room,
    this.initialView = BarChartViewSelection.grammar,
  });

  @override
  RoomDetailsAnalyticsState createState() => RoomDetailsAnalyticsState();
}

class RoomDetailsAnalyticsState extends State<RoomDetailsAnalytics> {
  @override
  void initState() {
    super.initState();
    // when you go to look at room details, you'll see analytics
    // for all the participants in the room. Non-admins most likely
    // not be in other user's analytics room, so try to join them
    // to make the analytics visible. This is a temporary solution
    // until analytics data is made available by the bot.
    super.initState();
    if (widget.room.isSpace) {
      widget.room.joinAnalyticsRoomsInSpace().then((_) => setState(() {}));
      return;
    }

    final spaceParents = widget.room.pangeaSpaceParents;
    if (spaceParents.isEmpty) return;
    spaceParents.first.joinAnalyticsRoomsInSpace();
  }

  bool isOpen = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Text(
            widget.room.isSpace
                ? L10n.of(context)!.spaceAnalytics
                : L10n.of(context)!.chatAnalytics,
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          titleAlignment: ListTileTitleAlignment.center,
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            foregroundColor: Theme.of(context).textTheme.bodyLarge!.color,
            child: const Icon(Icons.analytics_outlined),
          ),
          trailing: Icon(
            isOpen
                ? Icons.keyboard_arrow_down_outlined
                : Icons.keyboard_arrow_right_outlined,
          ),
          onTap: () {
            setState(() => isOpen = !isOpen);
          },
        ),
        // if (!isOpen)
        //   Divider(
        //     height: 1,
        //     color: Theme.of(context).dividerColor,
        //   ),
        if (isOpen)
          Container(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: AnalyticsDetailsDisplay(
                id: widget.room.id,
                type: widget.room.isSpace
                    ? AnalyticsEntryType.space
                    : AnalyticsEntryType.room,
              ),
            ),
          ),
      ],
    );
  }
}

class AnalyticsDetailsDisplay extends StatefulWidget {
  final String id;
  final AnalyticsEntryType type;
  const AnalyticsDetailsDisplay({
    super.key,
    required this.id,
    required this.type,
  });

  @override
  AnalyticsDetailsDisplayState createState() => AnalyticsDetailsDisplayState();
}

class AnalyticsDetailsDisplayState extends State<AnalyticsDetailsDisplay> {
  final PangeaController _pangeaController = MatrixState.pangeaController;
  StreamSubscription? stateSub;
  BarChartViewSelection selectedView = BarChartViewSelection.messages;
  ChartAnalyticsModel? chartAnalytics;

  @override
  void initState() {
    // when there's a state alert from message analytics controller
    // refresh the page, so that the filters update
    setChartData();
    stateSub = _pangeaController.analytics.stateStream.listen((_) {
      setChartData();
    });
    super.initState();
  }

  @override
  void dispose() {
    stateSub?.cancel();
    super.dispose();
  }

  Room? get room => Matrix.of(context).client.getRoomById(widget.id);

  List<LanguageModel> get targetLanguages {
    switch (widget.type) {
      case AnalyticsEntryType.space:
      case AnalyticsEntryType.room:
        return room?.roomTargetLanguages() ?? [];
      case AnalyticsEntryType.student:
        return Matrix.of(context).client.targetLanguages(userIDs: [widget.id]);
      default:
        return [];
    }
  }

  Future<void> setChartData() async {
    try {
      chartAnalytics = await _pangeaController.analytics.getAnalyticsById(
        id: widget.id,
        type: widget.type,
      );
    } catch (err) {
      debugPrint("Error getting analytics: $err");
    } finally {
      setState(() {});
    }
  }

  void setSelectedView(BarChartViewSelection view) {
    selectedView = view;
    setChartData();
  }

  Widget get currentView {
    switch (selectedView) {
      case (BarChartViewSelection.grammar):
        return ConstructList(
          id: widget.id,
          type: widget.type,
          constructType: ConstructTypeEnum.grammar,
          pangeaController: _pangeaController,
        );
      case (BarChartViewSelection.vocab):
        return ConstructList(
          id: widget.id,
          type: widget.type,
          constructType: ConstructTypeEnum.vocab,
          pangeaController: _pangeaController,
        );
      case (BarChartViewSelection.messages):
        return MessagesBarChart(
          chartAnalytics: chartAnalytics,
        );
      default:
        return Center(child: Text(L10n.of(context)!.noDataFound));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 8.0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  AnalyticsViewButton(
                    value: selectedView,
                    onChange: setSelectedView,
                  ),
                  TimeSpanMenuButton(
                    value: _pangeaController.analytics.currentAnalyticsTimeSpan,
                    onChange:
                        _pangeaController.analytics.setCurrentAnalyticsTimeSpan,
                  ),
                ],
              ),
              AnalyticsLanguageButton(
                value: _pangeaController.analytics.currentAnalyticsLang,
                onChange: _pangeaController.analytics.setCurrentAnalyticsLang,
                languages: targetLanguages,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 8.0,
          ),
          child: currentView,
        ),
      ],
    );
  }
}
