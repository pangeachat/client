import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/constructs/construct_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LevelSummaryDialog extends StatelessWidget {
  final int level;
  final String analyticsRoomId;
  final String summaryStateEventId;

  const LevelSummaryDialog({
    super.key,
    required this.analyticsRoomId,
    required this.level,
    required this.summaryStateEventId,
  });

  @override
  Widget build(BuildContext context) {
    final Client client = Matrix.of(context).client;
    final futureSummary = client
        .getOneRoomEvent(analyticsRoomId, summaryStateEventId)
        .then((rawEvent) => ConstructSummary.fromJson(rawEvent.content));

    return FutureBuilder<ConstructSummary>(
      future: futureSummary,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return AlertDialog(
            title: Text(L10n.of(context).levelSummaryPopupTitle(level)),
            content: Text('Error: ${snapshot.error}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(L10n.of(context).close),
              ),
            ],
          );
        } else if (snapshot.hasData) {
          final summaryStateEvent = snapshot.data!;
          return AlertDialog(
            title: Text(L10n.of(context).levelSummaryPopupTitle(level)),
            content: Text(summaryStateEvent.textSummary),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(L10n.of(context).close),
              ),
            ],
          );
        } else {
          return const SizedBox.shrink();
        }
      },
    );
  }
}
