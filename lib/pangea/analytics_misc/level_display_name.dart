import 'package:flutter/material.dart';

import 'package:flutter_svg/svg.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2.0),
      child: FutureBuilder(
        future: MatrixState.pangeaController.userController.getPublicProfile(
          userId,
        ),
        builder: (context, snapshot) {
          final analytics = snapshot.data?.analytics;
          final base = analytics?.baseLanguage;
          final target = analytics?.targetLanguage;
          final level = analytics?.level;

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
                  spacing: 4.0,
                  children: [
                    if (base != null && target != null) ...[
                      SvgPicture.network(
                        base.svgUrl.toString(),
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        placeholderBuilder: (_) => Center(
                          child: const CircularProgressIndicator(
                            strokeWidth: 0.5,
                          ),
                        ),
                        width: iconSize ?? 12.0,
                        height: iconSize ?? 12.0,
                      ),
                      Text(
                        base.langCodeShort.toUpperCase(),
                        style:
                            textStyle ??
                            TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      Icon(
                        Icons.chevron_right_outlined,
                        size: iconSize ?? 16.0,
                      ),
                    ],
                    if (target != null) ...[
                      SvgPicture.network(
                        target.svgUrl.toString(),
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        placeholderBuilder: (_) => Center(
                          child: const CircularProgressIndicator(
                            strokeWidth: 0.5,
                          ),
                        ),
                        width: iconSize ?? 12.0,
                        height: iconSize ?? 12.0,
                      ),
                      Text(
                        target.langCodeShort.toUpperCase(),
                        style:
                            textStyle ??
                            TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                    const SizedBox(width: 4.0),
                    if (level != null) ...[
                      Text("⭐", style: textStyle),
                      Text(
                        "$level",
                        style:
                            textStyle ??
                            TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
