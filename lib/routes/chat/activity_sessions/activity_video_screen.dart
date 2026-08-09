import 'package:flutter/material.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_video_player.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_youtube_player.dart';

/// Full-screen in-app player for a single activity video (YouTube or uploaded),
/// pushed as a route on native mobile.
///
/// On native mobile the plan page is a draggable bottom sheet, and a live player
/// is a platform view (webview) that can't sit inside a scrolling sheet: it
/// escapes the sheet's bounds (#7673) and its drag gestures force the embed into
/// an inexitable fullscreen (#7672). Playing on its own screen sidesteps both —
/// there is no scroll container to fight, and the app bar's close is an obvious,
/// always-present way back. Web and desktop keep playing inline in the hero /
/// carousel, where a platform view behaves; see [openActivityVideo].
class ActivityVideoScreen extends StatelessWidget {
  final ActivityMediaBlock block;

  const ActivityVideoScreen({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    // The user tapped to open this, so it may start with sound.
    final player = block.isYoutube
        ? ActivityYoutubePlayer(url: block.url ?? '')
        : ActivityVideoPlayer(url: block.resolvedUrl ?? '', autoPlay: true);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: L10n.of(context).close,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Center(
        child: AspectRatio(aspectRatio: 16 / 9, child: player),
      ),
    );
  }
}

/// Opens [block] full-screen over everything (root navigator, so it clears the
/// plan's bottom sheet). Native mobile only; callers keep inline playback on web
/// and desktop.
Future<void> openActivityVideo(BuildContext context, ActivityMediaBlock block) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ActivityVideoScreen(block: block),
    ),
  );
}
