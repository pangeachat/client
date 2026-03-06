import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';

class ActivityExampleMessage extends StatelessWidget {
  final Future<List<InlineSpan>?> future;

  const ActivityExampleMessage(this.future, {super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InlineSpan>?>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              Colors.white.withAlpha(180),
              ThemeData.dark().colorScheme.primary,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryFixed,
                fontSize:
                    AppSettings.fontSizeFactor.value *
                    AppConfig.messageFontSize,
              ),
              children: snapshot.data!,
            ),
          ),
        );
      },
    );
  }
}
