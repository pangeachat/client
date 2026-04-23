import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/url_image_widget.dart';

class MxcImageViewer extends StatelessWidget {
  final Uri mxContent;

  const MxcImageViewer(this.mxContent, {super.key});

  @override
  Widget build(BuildContext context) {
    final iconButtonStyle = IconButton.styleFrom(
      backgroundColor: Colors.black.withAlpha(200),
      foregroundColor: Colors.white,
    );
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black.withAlpha(128),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          elevation: 0,
          leading: IconButton(
            style: iconButtonStyle,
            icon: const Icon(Icons.close),
            onPressed: Navigator.of(context).pop,
            color: Colors.white,
            tooltip: L10n.of(context).close,
          ),
          backgroundColor: Colors.transparent,
        ),
        body: InteractiveViewer(
          minScale: 1.0,
          maxScale: 10.0,
          onInteractionEnd: (endDetails) {
            if (endDetails.velocity.pixelsPerSecond.dy >
                MediaQuery.sizeOf(context).height * 1.5) {
              Navigator.of(context, rootNavigator: false).pop();
            }
          },
          child: Center(
            child: GestureDetector(
              // Ignore taps to not go back here:
              onTap: () {},
              // #Pangea
              // child: MxcImage(
              //   key: ValueKey(mxContent.toString()),
              //   uri: mxContent,
              //   fit: BoxFit.contain,
              //   isThumbnail: false,
              //   animated: true,
              // ),
              child: ImageByUrl(
                key: ValueKey(mxContent.toString()),
                imageUrl: mxContent,
                fit: BoxFit.contain,
                isThumbnail: false,
              ),
              // Pangea#
            ),
          ),
        ),
      ),
    );
  }
}
