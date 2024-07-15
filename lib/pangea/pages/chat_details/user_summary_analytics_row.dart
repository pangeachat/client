import 'dart:async';

import 'package:fluffychat/pangea/enum/construct_type_enum.dart';
import 'package:fluffychat/pangea/enum/progress_indicators_enum.dart';
import 'package:fluffychat/pangea/enum/time_span.dart';
import 'package:fluffychat/pangea/extensions/client_extension/client_extension.dart';
import 'package:fluffychat/pangea/models/analytics/chart_analytics_model.dart';
import 'package:fluffychat/pangea/models/analytics/construct_list_model.dart';
import 'package:fluffychat/pangea/models/analytics/constructs_event.dart';
import 'package:fluffychat/pangea/pages/analytics/base_analytics.dart';
import 'package:fluffychat/pangea/utils/bot_name.dart';
import 'package:fluffychat/pangea/utils/bot_style.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

class UserSummaryAnalyticsRow extends StatefulWidget {
  final String userID;
  const UserSummaryAnalyticsRow({
    super.key,
    required this.userID,
  });

  @override
  UserSummaryAnalyticsRowState createState() => UserSummaryAnalyticsRowState();
}

class UserSummaryAnalyticsRowState extends State<UserSummaryAnalyticsRow> {
  ChartAnalyticsModel? chartAnalytics;
  ConstructListModel? grammarConstructs;
  ConstructListModel? vocabConstructs;
  StreamSubscription? stateSub;

  @override
  void initState() {
    setData();
    stateSub = MatrixState.pangeaController.analytics.stateStream.listen((_) {
      setData();
    });
    super.initState();
  }

  @override
  void dispose() {
    stateSub?.cancel();
    super.dispose();
  }

  Future<void> setChartData() async {
    try {
      chartAnalytics =
          await MatrixState.pangeaController.analytics.getAnalyticsById(
        id: widget.userID,
        type: AnalyticsEntryType.student,
        timeSpan: TimeSpan.forever,
      );
    } catch (err) {
      debugPrint("Error getting analytics: $err");
    }
  }

  Future<ConstructListModel?> getConstructs(
    ConstructTypeEnum type,
  ) async {
    final List<ConstructAnalyticsEvent>? constructEvents =
        await MatrixState.pangeaController.analytics.getConstructsById(
      id: widget.userID,
      type: AnalyticsEntryType.student,
      constructType: type,
      timeSpan: TimeSpan.forever,
    );
    return ConstructListModel(
      type: type,
      constructEvents: constructEvents ?? [],
    );
  }

  Future<void> setGrammarConstructs() async {
    try {
      grammarConstructs = await getConstructs(ConstructTypeEnum.grammar);
    } catch (err) {
      debugPrint("Error getting grammar constructs: $err");
    }
  }

  Future<void> setVocabConstructs() async {
    try {
      vocabConstructs = await getConstructs(ConstructTypeEnum.vocab);
    } catch (err) {
      debugPrint("Error getting vocab constructs: $err");
    }
  }

  void setData() async {
    final dataFutures = [
      setChartData(),
      setGrammarConstructs(),
      setVocabConstructs(),
    ];
    await Future.wait(dataFutures);
    if (mounted) {
      setState(() {});
    }
  }

  int? getDataByIndicator(ProgressIndicatorEnum indicator) {
    switch (indicator) {
      case ProgressIndicatorEnum.messagesSent:
        return chartAnalytics?.totals.all;
      case ProgressIndicatorEnum.errorTypes:
        return grammarConstructs?.lemmas.length;
      case ProgressIndicatorEnum.wordsUsed:
        return vocabConstructs?.lemmas.length;
      case ProgressIndicatorEnum.level:
        return level;
    }
  }

  bool get dataAvailable => Matrix.of(context).client.userAnalyticsAvailable(
        userID: widget.userID,
      );

  int get level {
    if (!dataAvailable) {
      return 0;
    }
    final int errorTypes = grammarConstructs?.lemmas.length ?? 0;
    final int wordsUsed = vocabConstructs?.lemmas.length ?? 0;
    return (errorTypes + wordsUsed) ~/ 100;
  }

  List<Widget> get indicators {
    return ProgressIndicatorEnum.values
        .map(
          (indicator) => Padding(
            padding: const EdgeInsets.only(right: 25),
            child: Tooltip(
              message: dataAvailable
                  ? indicator.tooltip(context)
                  : L10n.of(context)!.notAvailable,
              child: Row(
                children: [
                  Icon(
                    indicator.icon,
                    color: indicator.color(context),
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "${getDataByIndicator(indicator) ?? 0}",
                    style: BotStyle.text(context),
                  ),
                ],
              ),
            ),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userID == BotName.byEnvironment) {
      return const SizedBox();
    }

    return Opacity(
      opacity: dataAvailable ? 1 : 0.5,
      child: Row(children: indicators),
    );
  }
}
