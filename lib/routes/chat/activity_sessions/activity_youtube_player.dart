import 'package:flutter/material.dart';

import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Inline YouTube embed for an activity media block. YouTube blocks are always
/// embedded against their URL, never re-hosted (YouTube ToS), and this is the
/// one player that runs on both Flutter web and mobile.
///
/// When [muted] (the deep-link autoplay case) it autostarts silently so the
/// browser permits autoplay; with sound it relies on the user's tap as the
/// gesture. Only the carousel's active page should mount one — it owns an
/// iframe/webview that must be torn down with [YoutubePlayerController.close].
class ActivityYoutubePlayer extends StatefulWidget {
  final String url;
  final bool muted;
  final double aspectRatio;

  const ActivityYoutubePlayer({
    required this.url,
    this.muted = false,
    this.aspectRatio = 16 / 9,
    super.key,
  });

  @override
  State<ActivityYoutubePlayer> createState() => _ActivityYoutubePlayerState();
}

class _ActivityYoutubePlayerState extends State<ActivityYoutubePlayer> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      params: YoutubePlayerParams(
        mute: widget.muted,
        showControls: true,
        playsInline: true,
        privacyEnhancedMode: true,
      ),
    );
    final id = YoutubePlayerController.convertUrlToId(widget.url);
    if (id != null) {
      // loadVideoById autoplays (allowed because we start muted, or because the
      // mount followed a user tap).
      _controller.loadVideoById(videoId: id);
    }
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayer(
      controller: _controller,
      aspectRatio: widget.aspectRatio,
    );
  }
}
