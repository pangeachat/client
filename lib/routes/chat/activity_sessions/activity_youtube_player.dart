import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Inline YouTube embed for an activity media block. YouTube blocks are always
/// embedded against their URL, never re-hosted (YouTube ToS), and this is the
/// one player that runs on both Flutter web and mobile.
///
/// When [muted] (the deep-link autoplay case) it autostarts silently so the
/// browser permits autoplay; with sound it relies on the user's tap as the
/// gesture. Only the carousel's active page should mount one — it owns an
/// iframe/webview that must be torn down with [YoutubePlayerController.close].
///
/// Captions follow YouTube's default, which is on, and we name the track:
/// [captionLanguage], the activity's target language, so an L2 video captions
/// in the L2. We don't force them on (`cc_load_policy` stays off), but that is
/// a no-op: the embed can't see the learner's YouTube setting and shows
/// captions anyway. The package's defaults would also hardcode English. On
/// native we clear YouTube's remembered caption language before each video so
/// the activity's language wins; see [_forgetStickyCaptionLanguage] (#8828).
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

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      params: YoutubePlayerParams(
        mute: widget.muted,
        showControls: true,
        playsInline: true,
        // Not forced on, and preferred in the activity's language — see the
        // class doc (#8828). The preference applies with `cc_load_policy`
        // unset, whatever the package's own comment claims. Empty leaves it
        // unset, which is what an unknown activity language should do — the
        // package's default would instead name English.
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
    if (id != null) _loadVideo(id);
  }

  Future<void> _loadVideo(String id) async {
    if (!kIsWeb) await _forgetStickyCaptionLanguage();
    if (!mounted) return;
    // loadVideoById autoplays (allowed because we start muted, or because the
    // mount followed a user tap).
    await _controller.loadVideoById(videoId: id);
  }

  /// Removes the caption language YouTube remembers from the last time the
  /// learner turned captions on, which would otherwise outrank `cc_lang_pref`
  /// for 30 days on every video (#8828). Native only: there the player page
  /// runs under the embed's own origin and so shares its localStorage; on web
  /// the embed's storage belongs to a cross-origin frame we can't reach.
  Future<void> _forgetStickyCaptionLanguage() async {
    try {
      // Any player query waits for the player page to be ready.
      await _controller.playerState;
      await _controller.webViewController.runJavaScript(
        "localStorage.removeItem('yt-player-caption-sticky-language')",
      );
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {'url': widget.url});
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
