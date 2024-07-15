import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pangea/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/enum/construct_type_enum.dart';
import 'package:fluffychat/pangea/enum/progress_indicators_enum.dart';
import 'package:fluffychat/pangea/pages/analytics/base_analytics.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

/// A summary of "My Analytics" shown at the top of the chat list
/// It shows a variety of progress indicators such as
/// messages sent,  words used, and error types, which can
/// be clicked to access more fine-grained analytics data.
class LearningProgressIndicators extends StatefulWidget {
  const LearningProgressIndicators({
    super.key,
  });

  @override
  LearningProgressIndicatorsState createState() =>
      LearningProgressIndicatorsState();
}

class LearningProgressIndicatorsState
    extends State<LearningProgressIndicators> {
  final PangeaController _pangeaController = MatrixState.pangeaController;
  int? messagesSent;
  int? wordsUsed;
  int? errorTypes;

  @override
  void initState() {
    super.initState();
    setData();
  }

  AnalyticsSelected get defaultSelected => AnalyticsSelected(
        _pangeaController.matrixState.client.userID!,
        AnalyticsEntryType.student,
        "",
      );

  Future<void> setData() async {
    final futures = [
      setMessagesSent(),
      setWordsUsed(),
      setErrorTypes(),
    ];
    await Future.wait(futures);
    setState(() {});
  }

  Future<void> setMessagesSent() async {
    final analytics = await _pangeaController.analytics
        .getAnalytics(defaultSelected: defaultSelected);
    messagesSent = analytics.msgs.length;
  }

  Future<void> setWordsUsed() async {
    wordsUsed = await getNumLemmasUsed(ConstructTypeEnum.vocab);
  }

  Future<void> setErrorTypes() async {
    errorTypes = await getNumLemmasUsed(ConstructTypeEnum.grammar);
  }

  Future<int> getNumLemmasUsed(ConstructTypeEnum type) async {
    final constructs = await _pangeaController.analytics.getConstructs(
      defaultSelected: defaultSelected,
      constructType: type,
    );
    if (constructs == null) return 0;
    final List<String> lemmas = [];
    for (final event in constructs) {
      for (final use in event.content.uses) {
        if (use.lemma == null) continue;
        lemmas.add(use.lemma!);
      }
    }
    return lemmas.toSet().length;
  }

  int? getProgressPoints(ProgressIndicatorEnum indicator) {
    switch (indicator) {
      case ProgressIndicatorEnum.messagesSent:
        return messagesSent;
      case ProgressIndicatorEnum.wordsUsed:
        return wordsUsed;
      case ProgressIndicatorEnum.errorTypes:
        return errorTypes;
      case ProgressIndicatorEnum.level:
        return level;
    }
  }

  int get xpPoints {
    final points = [
      messagesSent ?? 0,
      wordsUsed ?? 0,
      errorTypes ?? 0,
    ];
    return points.reduce((a, b) => a + b);
  }

  int get level => xpPoints ~/ 100;

  Widget get avatar => FutureBuilder(
        future: _pangeaController.matrixState.client.getProfileFromUserId(
          _pangeaController.matrixState.client.userID!,
        ),
        builder: (context, snapshot) {
          final mxid =
              Matrix.of(context).client.userID ?? L10n.of(context)!.user;
          return Avatar(
            name: snapshot.data?.displayName ?? mxid.localpart ?? mxid,
            mxContent: snapshot.data?.avatarUrl,
          );
        },
      );

  Widget get progressBar => LinearProgressIndicator(
        value: (xpPoints % 100) / 100,
        color: Theme.of(context).colorScheme.primary,
        backgroundColor: Theme.of(context).colorScheme.onPrimary,
        minHeight: 15,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      );

  Widget get indicators => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: ProgressIndicatorEnum.values
            .where(
              (indicator) => indicator != ProgressIndicatorEnum.level,
            )
            .map(
              (indicator) => ProgressIndicatorView(
                points: getProgressPoints(indicator),
                onTap: () {},
                progressIndicator: indicator,
              ),
            )
            .toList(),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 36,
        vertical: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              avatar,
              Expanded(child: indicators),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 35,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  right: 0,
                  child: Row(
                    children: [
                      SizedBox(
                        width: FluffyThemes.columnWidth - (36 * 2) - 25,
                        child: progressBar,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  child: CircleAvatar(
                    backgroundColor: "$level $xpPoints".lightColorAvatar,
                    radius: 16,
                    child: Text(
                      "$level",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProgressIndicatorView extends StatelessWidget {
  final int? points;
  final VoidCallback onTap;
  final ProgressIndicatorEnum progressIndicator;

  const ProgressIndicatorView({
    super.key,
    required this.points,
    required this.onTap,
    required this.progressIndicator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: Tooltip(
        message: progressIndicator.tooltip(context),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  progressIndicator.icon,
                  color: progressIndicator.color(context),
                ),
                const SizedBox(width: 5),
                points != null
                    ? Text(
                        points.toString(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : const CircularProgressIndicator.adaptive(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
