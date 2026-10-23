import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

class InsufficientDataIndicator extends StatelessWidget {
  /// The session was to run offline, from what this device has saved.
  final bool offline;

  const InsufficientDataIndicator({this.offline = false, super.key});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: RichText(
        textScaler: MediaQuery.textScalerOf(context),
        textAlign: TextAlign.center,
        text: TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.info_outline, size: 24.0),
            ),
            TextSpan(text: '  '),
            TextSpan(
              text: offline
                  ? L10n.of(context).offlinePracticeNothingSaved
                  : L10n.of(context).noAnalyticsActivitiesAvailable,
              style: DefaultTextStyle.of(context).style,
            ),
          ],
        ),
      ),
    );
  }
}
