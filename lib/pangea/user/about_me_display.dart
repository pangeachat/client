import 'package:flutter/material.dart';

import 'package:fluffychat/widgets/matrix.dart';

class AboutMeDisplay extends StatelessWidget {
  final String userId;
  final double maxWidth;
  final double textSize;

  const AboutMeDisplay({
    super.key,
    required this.userId,
    this.maxWidth = 200,
    this.textSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FutureBuilder(
        future: MatrixState.pangeaController.userController.getPublicProfile(
          userId,
        ),
        builder: (context, snapshot) => snapshot.data?.about == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  snapshot.data!.about!,
                  style: TextStyle(fontSize: textSize),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
      ),
    );
  }
}
