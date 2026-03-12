import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';

class AnalyticsInitErrorIndicator extends StatelessWidget {
  final VoidCallback reinitialize;
  const AnalyticsInitErrorIndicator({super.key, required this.reinitialize});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ErrorIndicator(message: L10n.of(context).oopsSomethingWentWrong),
          SizedBox(height: 8.0),
          TextButton(
            onPressed: reinitialize,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh),
                SizedBox(width: 4.0),
                Text(L10n.of(context).tryAgain),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
