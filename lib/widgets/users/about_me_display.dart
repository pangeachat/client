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
        builder: (context, snapshot) {
          final about = snapshot.data?.about;
          return about == null
              ? const SizedBox.shrink()
              : AboutMeText(about: about, textSize: textSize);
        },
      ),
    );
  }
}

/// The about-me body: a vertically scrollable block of WRAPPING text. It wraps
/// at the width of the surrounding box (an ancestor `ConstrainedBox(maxWidth:)`)
/// and scrolls within [maxHeight]. Previously the text sat inside a `Row`, which
/// gave it unbounded width so a long bio never wrapped and spilled out of the
/// box — and the `overflow: ellipsis` could not trigger inside an unbounded Row
/// (#7117). It is a shared widget, so this fixes both the mini profile popup and
/// the larger profile.
@visibleForTesting
class AboutMeText extends StatelessWidget {
  final String about;
  final double textSize;
  final double maxHeight;

  const AboutMeText({
    super.key,
    required this.about,
    required this.textSize,
    this.maxHeight = 100.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Text(about, style: TextStyle(fontSize: textSize)),
      ),
    );
  }
}
