import 'dart:math';

import 'package:flutter/material.dart';

import 'package:carousel_slider/carousel_slider.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_play_badge.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_video_player.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_video_screen.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_youtube_player.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

/// The focused-surface media display for an activity (plan page and live
/// session): a per-block carousel over the activity's media list. Images render
/// directly; video and YouTube blocks render as a thumbnail with a play badge
/// and only mount a live player when tapped — one live player at a time, and
/// nothing autostarts, so the carousel stays calm. The exception is
/// [autoplayIndex], which starts that block muted for the thumbnail deep link.
///
/// Degrades to a single, un-navigable display when there is one renderable
/// block, and to [fallbackImageUrl] (the legacy single image / placeholder)
/// when there is none.
class ActivityMediaCarousel extends StatefulWidget {
  final List<ActivityMediaBlock> media;

  /// Single-image / placeholder fallback (the activity's `imageURL`) for when
  /// [media] has no renderable visual block.
  final Uri? fallbackImageUrl;
  final BorderRadius borderRadius;

  /// Index — into the visible (image/video/youtube) blocks — to autostart muted
  /// on first build, for the thumbnail-tap deep link. Null means nothing
  /// autostarts.
  final int? autoplayIndex;

  const ActivityMediaCarousel({
    required this.media,
    this.fallbackImageUrl,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.autoplayIndex,
    super.key,
  });

  @override
  State<ActivityMediaCarousel> createState() => _ActivityMediaCarouselState();
}

class _ActivityMediaCarouselState extends State<ActivityMediaCarousel> {
  /// Index currently mounting a live player, or null when every page is a still.
  int? _playingIndex;
  int _page = 0;

  /// True while the active play is the deep-link autostart (muted); cleared the
  /// moment the user taps a thumbnail, so tapped videos play with sound.
  bool _mutedAutostart = false;

  @override
  void initState() {
    super.initState();
    // On native mobile nothing mounts a live player inline (#7672/#7673): the
    // deep-link block still lands under the viewport, but as a thumbnail — tap
    // opens it on its own screen. Web/desktop keep the muted inline autostart.
    _playingIndex = PlatformInfos.isMobile ? null : widget.autoplayIndex;
    _page = widget.autoplayIndex ?? 0;
    _mutedAutostart = !PlatformInfos.isMobile && widget.autoplayIndex != null;
  }

  List<ActivityMediaBlock> get _visible =>
      widget.media.where((b) => b.isImage || b.isVideo || b.isYoutube).toList();

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(
          constraints.maxWidth,
          MediaQuery.sizeOf(context).height * 0.5,
        );

        if (visible.isEmpty) {
          return _cell(_fallback(size), size);
        }
        if (visible.length == 1) {
          return _cell(_buildPage(visible.first, 0, size), size);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: widget.borderRadius,
              child: SizedBox(
                width: size,
                child: CarouselSlider(
                  options: CarouselOptions(
                    height: size,
                    viewportFraction: 1.0,
                    enableInfiniteScroll: false,
                    initialPage: _page,
                    onPageChanged: (i, _) => setState(() {
                      _page = i;
                      // Swiping away stops playback — nothing autostarts on the
                      // page you land on.
                      if (i != _playingIndex) _playingIndex = null;
                    }),
                  ),
                  items: [
                    for (var i = 0; i < visible.length; i++)
                      _buildPage(visible[i], i, size),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _dots(visible.length),
          ],
        );
      },
    );
  }

  /// A square, clipped media cell — used for the single/empty (un-navigable)
  /// case.
  Widget _cell(Widget child, double size) => ClipRRect(
    borderRadius: widget.borderRadius,
    child: SizedBox(width: size, height: size, child: child),
  );

  Widget _fallback(double size) => ImageByUrl(
    imageUrl: widget.fallbackImageUrl,
    width: size,
    borderRadius: BorderRadius.zero,
    replacement: SizedBox(height: size),
  );

  Widget _buildPage(ActivityMediaBlock block, int index, double size) {
    if (block.isImage) {
      final url = block.displayUrl(size);
      return ImageByUrl(
        imageUrl: url != null ? Uri.tryParse(url) : widget.fallbackImageUrl,
        width: size,
        borderRadius: BorderRadius.zero,
        replacement: SizedBox(height: size),
      );
    }

    // video / youtube
    if (_playingIndex == index) {
      final muted = _mutedAutostart && index == widget.autoplayIndex;
      final player = block.isYoutube
          ? ActivityYoutubePlayer(url: block.url ?? '', muted: muted)
          : ActivityVideoPlayer(
              url: block.resolvedUrl ?? '',
              autoPlay: true,
              muted: muted,
            );
      return Center(
        child: AspectRatio(aspectRatio: 16 / 9, child: player),
      );
    }

    // thumbnail + play badge — tap to play (with sound)
    final thumb = block.displayUrl(size);
    return GestureDetector(
      onTap: () {
        // Native mobile can't mount a webview inside this scrolling surface
        // (#7672/#7673), so play on a dedicated screen; inline elsewhere.
        if (PlatformInfos.isMobile) {
          openActivityVideo(context, block);
          return;
        }
        setState(() {
          _playingIndex = index;
          _mutedAutostart = false;
        });
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          ImageByUrl(
            imageUrl: thumb != null ? Uri.tryParse(thumb) : null,
            width: size,
            borderRadius: BorderRadius.zero,
            replacement: SizedBox(
              width: size,
              height: size,
              child: const ColoredBox(color: Colors.black12),
            ),
          ),
          const ActivityMediaPlayBadge(size: 44),
        ],
      ),
    );
  }

  Widget _dots(int count) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: i == _page ? 1.0 : 0.3),
          ),
        ),
    ],
  );
}
