import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';

class PangeaLoginScaffold extends StatelessWidget {
  final String mainAssetPath;
  final Uint8List? mainAssetBytes;
  final List<Widget> children;
  final bool showAppName;

  const PangeaLoginScaffold({
    required this.children,
    this.mainAssetPath = "assets/pangea/PangeaChat_Glow_Logo.png",
    this.mainAssetBytes,
    this.showAppName = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 300,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 175,
                          height: 175,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.transparent,
                          ),
                          child: ClipOval(
                            child: mainAssetBytes != null
                                ? Image.memory(
                                    mainAssetBytes!,
                                    fit: BoxFit.cover,
                                  )
                                : Image.asset(
                                    mainAssetPath,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (showAppName)
                          Text(
                            AppConfig.applicationName,
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                        if (showAppName) const SizedBox(height: 12),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
