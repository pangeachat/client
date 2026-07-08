import 'package:flutter/material.dart';

import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

/// Plays an uploaded (non-Matrix) video from a resolved CDN URL, sized to its
/// carousel cell. The timeline's [EventVideoPlayer] is bound to a Matrix event
/// and downloads/decrypts its bytes; an activity-media block instead carries a
/// plain resolved URL, so this takes a URL and exposes [autoPlay]/[muted] for
/// the deep-link "start muted, tap to unmute" case.
///
/// Each instance holds a live decoder, so only the carousel's active page
/// should mount one — siblings stay thumbnails.
class ActivityVideoPlayer extends StatefulWidget {
  final String url;
  final double? aspectRatio;
  final bool autoPlay;
  final bool muted;

  const ActivityVideoPlayer({
    required this.url,
    this.aspectRatio,
    this.autoPlay = true,
    this.muted = false,
    super.key,
  });

  @override
  State<ActivityVideoPlayer> createState() => _ActivityVideoPlayerState();
}

class _ActivityVideoPlayerState extends State<ActivityVideoPlayer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _videoController = controller;
    try {
      await controller.initialize();
      if (widget.muted) await controller.setVolume(0);
      if (!mounted) return;
      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: controller,
          autoPlay: widget.autoPlay,
          looping: false,
          showControlsOnInitialize: false,
          // Inline only, matching the YouTube player: activity video is an
          // in-place stimulus, and fullscreen has no in-app exit here, so it
          // would trap the learner on a landscape tablet (#7500).
          allowFullScreen: false,
          aspectRatio: widget.aspectRatio ?? controller.value.aspectRatio,
        );
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(child: Icon(Icons.error_outline));
    }
    final chewie = _chewieController;
    if (chewie == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    return Chewie(controller: chewie);
  }
}
