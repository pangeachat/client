import 'dart:math';

import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/widgets/pangea_logo_svg.dart';

class EmptyPage extends StatelessWidget {
  static const double _width = 400;
  const EmptyPage({super.key});
  @override
  Widget build(BuildContext context) {
    final width = min(MediaQuery.of(context).size.width, EmptyPage._width) / 2;
    // #Pangea
    // final theme = Theme.of(context);
    // Pangea#
    return Scaffold(
      // Add invisible appbar to make status bar on Android tablets bright.
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        alignment: Alignment.center,
        // #Pangea
        child: PangeaLogoSvg(width: width),
        // child: Image.asset(
        //   'assets/logo_transparent.png',
        //   color: theme.colorScheme.surfaceContainerHigh,
        //   width: width,
        //   height: width,
        //   filterQuality: FilterQuality.medium,
        // ),
        // Pangea#
      ),
    );
  }
}
