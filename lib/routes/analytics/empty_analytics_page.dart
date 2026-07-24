import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/routes/analytics/analytics_page_constants.dart';

class EmptyAnalyticsPage extends StatelessWidget {
  const EmptyAnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 250.0,
          child: CachedNetworkImage(
            imageUrl:
                "${AppConfig.assetsBaseURL}/${AnalyticsPageConstants.dinoBotFileName}",
            errorWidget: (context, url, error) => const SizedBox(),
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator.adaptive()),
          ),
        ),
      ),
    );
  }
}
