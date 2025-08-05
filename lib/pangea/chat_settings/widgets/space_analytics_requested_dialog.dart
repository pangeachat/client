import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/analytics_page/analytics_page_constants.dart';
import 'package:fluffychat/pangea/common/widgets/full_width_dialog.dart';

class SpaceAnalyticsRequestedDialog extends StatelessWidget {
  final Room room;
  const SpaceAnalyticsRequestedDialog({
    super.key,
    required this.room,
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
                L10n.of(context).accessRequestedTitle,
                style: const TextStyle(fontSize: 24.0),
              ),
              Text(
                L10n.of(context).accessRequestedDesc(
                  room.getLocalizedDisplayname(),
                ),
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
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Row(
                        spacing: 10.0,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Symbols.approval_delegation),
                          Text(L10n.of(context).allowAccess),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Row(
                        spacing: 10.0,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.visibility_off),
                          Text(L10n.of(context).denyAccess),
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
