import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluffychat/pangea/activity_planner/activity_plan_model.dart';
import 'package:fluffychat/widgets/mxc_image.dart';

class ActivityPlanImage extends StatelessWidget {
  final ActivityPlanModel activity;
  final double width;
  final BorderRadius borderRadius;
  final Widget? replacement;

  const ActivityPlanImage(
    this.activity, {
    super.key,
    required this.width,
    this.borderRadius = const BorderRadius.all(Radius.circular(20.0)),
    this.replacement,
  });

  @override
  Widget build(BuildContext context) {
    final url = activity.imageURL;
    if (url == null) {
      return replacement ?? const SizedBox();
    }

    return SizedBox(
      width: width,
      height: width,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: url.startsWith("mxc")
            ? MxcImage(
                uri: Uri.parse(url),
                width: width,
                height: width,
                cacheKey: activity.bookmarkId,
                fit: BoxFit.cover,
              )
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (
                  context,
                  url,
                ) =>
                    const Center(
                  child: CircularProgressIndicator(),
                ),
                errorWidget: (
                  context,
                  url,
                  error,
                ) =>
                    replacement ?? const SizedBox(),
              ),
      ),
    );
  }
}
