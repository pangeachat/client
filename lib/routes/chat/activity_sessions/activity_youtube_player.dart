import 'package:flutter/material.dart';

import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:fluffychat/pangea/common/widgets/embed_click_to_engage.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_video_keyboard_control.dart';

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
/// The embed only takes the mouse once the learner clicks it, so the page
/// around it keeps scrolling while they are just passing over ([
/// EmbedClickToEngage], #9063). That first click spends itself on play/pause,
/// the same thing a click on a YouTube player does.
///
/// The embed stays inline: fullscreen is fully disabled (no fullscreen button,
/// no auto-fullscreen on landscape rotation, no fullscreen-on-vertical-drag).
/// Activity video is an in-place plan-page stimulus, and the package's
/// fullscreen has no in-app exit affordance the way we mount it, so on a
/// landscape tablet it would otherwise take over the screen with no way out and
/// trap the learner (#7500).
///
/// From the keyboard the player is one Tab stop that plays, mutes and switches
/// captions itself ([ActivityVideoKeyboardControl], #9128): Tab cannot enter
/// the frame, so YouTube's own controls are out of a keyboard's reach.
class ActivityYoutubePlayer extends StatefulWidget {
  final String url;
  final bool muted;
  final double aspectRatio;

  /// Preferred caption-track language — the activity's target language. Null or
  /// blank leaves the preference unset, so YouTube picks the track itself
  /// rather than us naming a language the activity isn't in.
  final String? captionLanguage;

  /// See [ActivityVideoKeyboardControl.autofocus].
  final bool autofocus;

  const ActivityYoutubePlayer({
    required this.url,
    this.muted = false,
    this.aspectRatio = 16 / 9,
    this.captionLanguage,
    this.autofocus = false,
    super.key,
  });

  /// [language] as the language code `cc_lang_pref` takes, or null when there
  /// is nothing usable to send. A localized code (`zh-Hans`, `en_US`) narrows
  /// to its base language, since a caption track is a language, not a script or
  /// region variant. Anything that isn't a bare two- or three-letter code is
  /// dropped rather than sent: `cc_lang_pref` is documented as ISO 639-1, but
  /// YouTube does carry tracks for the three-letter languages we teach (`haw`,
  /// `fil`, `yue`), so narrowing to two letters would lose them.
  static String? captionLanguageCode(String? language) {
    final code = language?.split(RegExp('[-_]')).first.trim().toLowerCase();
    if (code == null || !RegExp(r'^[a-z]{2,3}$').hasMatch(code)) return null;
    return code;
  }

  @override
  State<ActivityYoutubePlayer> createState() => _ActivityYoutubePlayerState();
}

class _ActivityYoutubePlayerState extends State<ActivityYoutubePlayer> {
  late final YoutubePlayerController _controller;

  /// The embed shows captions unless the viewer turned them off, whatever
  /// `cc_load_policy` says (#8828), so the first press of C turns them off.
  // ponytail: the frame's caption state cannot be read from here, so a learner
  // who also clicks YouTube's own CC button makes the next C press a no-op.
  bool _captionsOn = true;

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

  void _togglePlayback() {
    if (_controller.value.playerState == PlayerState.playing) {
      _controller.pauseVideo();
    } else {
      _controller.playVideo();
    }
  }

  Future<void> _toggleMute() async =>
      await _controller.isMuted ? _controller.unMute() : _controller.mute();

  /// Through the captions module, the one caption switch that takes a single
  /// argument: the package's web bridge drops calls with more. Turning them
  /// back on this way keeps the preferred caption language (measured, #9128).
  void _toggleCaptions() {
    _captionsOn = !_captionsOn;
    final call = _captionsOn ? 'loadModule' : 'unloadModule';
    _controller.webViewController.runJavaScript('player.$call("captions");');
  }

  @override
  Widget build(BuildContext context) {
    return ActivityVideoKeyboardControl(
      autofocus: widget.autofocus,
      onTogglePlayback: _togglePlayback,
      onToggleMute: _toggleMute,
      onToggleCaptions: _toggleCaptions,
      child: EmbedClickToEngage(
        onEngage: _togglePlayback,
        child: YoutubePlayer(
          controller: _controller,
          aspectRatio: widget.aspectRatio,
          // Inline only (#7500): don't auto-fullscreen on landscape rotation,
          // and don't let a vertical drag push into fullscreen.
          autoFullScreen: false,
          enableFullScreenOnVerticalDrag: false,
        ),
      ),
    );
  }
}
