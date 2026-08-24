import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/widgets/network_svg.dart';

/// A [NetworkSvg] with its colors swapped out — used for assets we tint to the
/// current theme (morph icons, analytics level icons).
class CustomizedSvg extends StatelessWidget {
  /// URL of the SVG file
  final String svgUrl;

  /// Map of color replacements
  final Map<String, String> colorReplacements;

  /// Icon to show in case of error
  final Widget errorIcon;

  final Widget? loadingPlaceholder;

  /// Width of the SVG
  /// Default is 24
  /// If you want to keep the aspect ratio, set only the height
  final double? width;

  /// Height of the SVG
  /// Default is 24
  /// If you want to keep the aspect ratio, set only the width
  final double? height;

  final BoxFit? fit;

  const CustomizedSvg({
    super.key,
    required this.svgUrl,
    this.colorReplacements = const {},
    this.errorIcon = const Icon(Icons.error_outline),
    this.loadingPlaceholder,
    this.width = 24,
    this.height = 24,
    this.fit,
  });

  /// Drops `fill="none"` so a replaced color actually paints, then applies the
  /// replacements.
  String _modifySVG(String svgContent) {
    String modifiedSvg = svgContent.replaceAll("fill=\"none\"", '');
    for (final entry in colorReplacements.entries) {
      modifiedSvg = modifiedSvg.replaceAll(entry.key, entry.value);
    }
    return modifiedSvg;
  }

  @override
  Widget build(BuildContext context) {
    return NetworkSvg(
      svgUrl: svgUrl,
      transform: _modifySVG,
      transformKey: colorReplacements.entries
          .map((e) => '${e.key}->${e.value}')
          .join(';'),
      errorWidget: errorIcon,
      placeholder:
          loadingPlaceholder ??
          SizedBox(
            width: width,
            height: height,
            child: const Center(child: CircularProgressIndicator()),
          ),
      width: width,
      height: height,
      fit: fit,
    );
  }
}

String colorToHex(Color color) {
  return '#'
      '${(color.r * 255).toInt().toRadixString(16).padLeft(2, '0')}'
      '${(color.g * 255).toInt().toRadixString(16).padLeft(2, '0')}'
      '${(color.b * 255).toInt().toRadixString(16).padLeft(2, '0')}';
}
