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
///
/// Captions are the learner's to turn on, not ours to impose: we set only the
/// preferred track language ([captionLanguage] — the activity's target
/// language, so an L2 video captions in the L2) and leave `cc_load_policy` off,
/// so the learner's own YouTube caption setting decides whether they show. The
/// package's defaults do the opposite — they force captions on and hardcode a
/// preference of English (#8828).
///
/// The embed stays inline: fullscreen is fully disabled (no fullscreen button,
/// no auto-fullscreen on landscape rotation, no fullscreen-on-vertical-drag).
/// Activity video is an in-place plan-page stimulus, and the package's
/// fullscreen has no in-app exit affordance the way we mount it, so on a
/// landscape tablet it would otherwise take over the screen with no way out and
/// trap the learner (#7500).
class ActivityYoutubePlayer extends StatefulWidget {
  final String url;
  final bool muted;
  final double aspectRatio;

  /// Preferred caption-track language — the activity's target language. Null or
  /// blank leaves the preference unset, so YouTube picks the track itself
  /// rather than us naming a language the activity isn't in.
  final String? captionLanguage;

  const ActivityYoutubePlayer({
    required this.url,
    this.muted = false,
    this.aspectRatio = 16 / 9,
    this.captionLanguage,
    super.key,
  });

  /// [language] as the ISO 639-1 two-letter code `cc_lang_pref` takes, or null
  /// when there is nothing usable to send — a localized code (`zh-Hans`)
  /// narrows to its base language, since a caption track is what YouTube has,
  /// not a script variant.
  static String? captionLanguageCode(String? language) {
    final code = language?.split('-').first.trim().toLowerCase();
    return (code == null || code.isEmpty) ? null : code;
  }

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
        // Captions off by default and preferred in the activity's language —
        // see the class doc (#8828). The preference still applies with
        // `cc_load_policy` unset: YouTube's parameter reference says captions
        // "will display in the specified language if the user opts to turn
        // captions on" (the package's own comment, claiming the preference is
        // ignored here, contradicts that). Empty leaves it unset, which is what
        // an unknown activity language should do — the package's default would
        // instead name English.
        enableCaption: false,
        captionLanguage:
            ActivityYoutubePlayer.captionLanguageCode(widget.captionLanguage) ??
            '',
        // Keep it inline — see the class doc (#7500). Already the package
        // default, but pinned so it can't silently flip back on.
        showFullscreenButton: false,
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
      // Inline only (#7500): don't auto-fullscreen on landscape rotation, and
      // don't let a vertical drag push into fullscreen.
      autoFullScreen: false,
      enableFullScreenOnVerticalDrag: false,
    );
  }
}
