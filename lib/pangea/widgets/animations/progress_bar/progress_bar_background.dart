import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/widgets/animations/progress_bar/progress_bar_details.dart';
import 'package:flutter/material.dart';

class ProgressBarBackground extends StatelessWidget {
  final ProgressBarDetails details;

  const ProgressBarBackground({
    super.key,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: details.height,
      width: details.totalWidth,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(
          Radius.circular(AppConfig.borderRadius),
        ),
        color: details.borderColor.withOpacity(0.2),
      ),
    );
  }
}
