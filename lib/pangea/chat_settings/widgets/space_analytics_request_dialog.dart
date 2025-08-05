import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_page/analytics_page_constants.dart';
import 'package:fluffychat/pangea/common/widgets/full_width_dialog.dart';

class SpaceAnalyticsRequestDialog extends StatelessWidget {
  final int count;
  const SpaceAnalyticsRequestDialog({
    super.key,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return FullWidthDialog(
      maxHeight: 800.0,
      maxWidth: 600.0,
      dialogContent: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 40.0,
          ),
          child: Column(
            spacing: 12.0,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.of(context).requestAccessTitle,
                style: const TextStyle(fontSize: 24.0),
              ),
              Text(
                L10n.of(context).requestAccessDesc,
                style: const TextStyle(fontSize: 16.0),
              ),
              CachedNetworkImage(
                imageUrl:
                    "${AppConfig.assetsBaseURL}/${AnalyticsPageConstants.dinoBotFileName}",
                errorWidget: (context, e, s) => const SizedBox.shrink(),
                progressIndicatorBuilder: (context, _, __) =>
                    const SizedBox.shrink(),
                width: 300.0,
              ),
              Row(
                spacing: 20.0,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Row(
                        spacing: 10.0,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.close),
                          Text(L10n.of(context).cancel),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Row(
                        spacing: 10.0,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Symbols.approval_delegation),
                          Text(L10n.of(context).requestAccess(count)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
