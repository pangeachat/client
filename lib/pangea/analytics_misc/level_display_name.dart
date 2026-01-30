import 'package:flutter/material.dart';

import 'package:fluffychat/widgets/matrix.dart';

class LevelDisplayName extends StatelessWidget {
  final String userId;
  final TextStyle? textStyle;
  final double? iconSize;

  const LevelDisplayName({
    required this.userId,
    this.textStyle,
    this.iconSize,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 0,
        vertical: 2.0,
      ),
      child: FutureBuilder(
        future: MatrixState.pangeaController.userController
            .getPublicProfile(userId),
        builder: (context, snapshot) {
          final analytics = snapshot.data?.analytics;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (!snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: SizedBox(
                    width: 12.0,
                    height: 12.0,
                    child: CircularProgressIndicator.adaptive(),
                  ),
                )
              else if (snapshot.hasError || snapshot.data == null)
                const SizedBox()
              else
                Row(
                  children: [
                    if (snapshot.data?.countryEmoji != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4.0),
                        child: Text(
                          snapshot.data!.countryEmoji!,
                          style: textStyle ??
                              const TextStyle(
                                fontSize: 16.0,
                              ),
                        ),
                      ),
                    if (analytics?.baseLanguage != null &&
                        analytics?.targetLanguage != null)
                      Text(
                        analytics!.baseLanguage!.langCodeShort.toUpperCase(),
                        style: textStyle ??
                            TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    if (analytics?.baseLanguage != null &&
                        analytics?.targetLanguage != null)
                      Icon(
                        Icons.chevron_right_outlined,
                        size: iconSize ?? 16.0,
                      ),
                    if (analytics?.targetLanguage != null)
                      Text(
                        analytics!.targetLanguage!.langCodeShort.toUpperCase(),
                        style: textStyle ??
                            TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    const SizedBox(width: 4.0),
                    if (analytics?.level != null)
                      Text(
                        "⭐",
                        style: textStyle,
                      ),
                    if (analytics?.level != null)
                      Text(
                        "${analytics!.level!}",
                        style: textStyle ??
                            TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
