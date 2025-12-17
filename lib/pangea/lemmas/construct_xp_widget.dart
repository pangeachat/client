import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/analytics_misc/construct_use_model.dart';
import 'package:fluffychat/pangea/constructs/construct_level_enum.dart';

class ConstructXpWidget extends StatelessWidget {
  final ConstructUses construct;
  final VoidCallback? onTap;
  final double size;

  const ConstructXpWidget({
    required this.construct,
    super.key,
    this.onTap,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final svg = construct.lemmaCategory.icon();
    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Stack(
            alignment: Alignment.center,
            children: [
              svg,
            ],
          ),
        ),
      ),
    );
  }
}
