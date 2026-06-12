// #Pangea
// import 'dart:math';
// Pangea#

import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/world/widgets/world_map.dart';

// #Pangea
// import 'package:fluffychat/pangea/common/widgets/pangea_logo_svg.dart';
// Pangea#

class EmptyPage extends StatelessWidget {
  // #Pangea
  // static const double _width = 400;
  // Pangea#
  const EmptyPage({super.key});
  @override
  Widget build(BuildContext context) {
    // #Pangea
    // final width = min(MediaQuery.sizeOf(context).width, EmptyPage._width) / 2;
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
      // #Pangea
      body: const WorldMap(),
      // body: Container(
      //   alignment: Alignment.center,
      //   child: Image.asset(
      //     'assets/logo_transparent.png',
      //     color: theme.colorScheme.surfaceContainerHigh,
      //     width: width,
      //     height: width,
      //     filterQuality: FilterQuality.medium,
      //   ),
      // ),
      // Pangea#
    );
  }
}
