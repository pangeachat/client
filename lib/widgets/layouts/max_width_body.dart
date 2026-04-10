import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

class MaxWidthBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final bool withScrolling;
  final EdgeInsets? innerPadding;
  // #Pangea
  final bool showBorder;
  final EdgeInsets? padding;
  final ScrollController? scrollController;
  final bool addVerticalPadding;
  // Pangea#

  const MaxWidthBody({
    required this.child,
    this.maxWidth = 600,
    this.withScrolling = true,
    this.innerPadding,
    // #Pangea
    this.showBorder = true,
    this.padding,
    this.scrollController,
    this.addVerticalPadding = true,
    // Pangea#
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final theme = Theme.of(context);

          // #Pangea
          // const desiredWidth = FluffyThemes.columnWidth * 1.5;
          final desiredWidth = maxWidth;
          // Pangea#
          final body = constraints.maxWidth <= desiredWidth
              ? child
              : Container(
                  alignment: Alignment.topCenter,
                  // #Pangea
                  // padding: const EdgeInsets.all(32),
                  padding: padding ?? const EdgeInsets.all(32),
                  // Pangea#
                  child: ConstrainedBox(
                    // #Pangea
                    // constraints: const BoxConstraints(
                    //   maxWidth: FluffyThemes.columnWidth * 1.5,
                    // ),
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    // Pangea#
                    child: Material(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius,
                        ),
                        // #Pangea
                        // side: BorderSide(color: theme.dividerColor),
                        side: BorderSide(
                          color: showBorder
                              ? theme.dividerColor
                              : Colors.transparent,
                        ),
                        // Pangea#
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Padding(
                        // #Pangea
                        // padding: const EdgeInsets.symmetric(vertical: 16.0),
                        padding: addVerticalPadding
                            ? const EdgeInsets.symmetric(vertical: 16.0)
                            : EdgeInsets.zero,
                        // Pangea#
                        child: child,
                      ),
                    ),
                  ),
                );
          if (!withScrolling) return body;

          return SingleChildScrollView(
            padding: innerPadding,
            // #Pangea
            controller: scrollController,
            // Pangea#
            physics: const ScrollPhysics(),
            child: body,
          );
        },
      ),
    );
  }
}
