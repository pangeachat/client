import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_visibility.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

/// The opt-in activity image behind an activity chat
/// (`AppSettings.activityImageAsChatBackground`, followed live so a change in
/// settings reaches a chat that is already open). It fades in as the
/// activity's media carousel scrolls out of view and back out as it returns,
/// so the background and the tappable image never show at the same time. Its
/// backdrop covers the learner's own wallpaper as it fades in, crossfading the
/// two. See activities.instructions.md.
class ActivityChatBackground extends StatefulWidget {
  final Uri imageUrl;
  final double blur;
  final ActivityMediaVisibility mediaVisibility;
  final ScrollController scrollController;

  const ActivityChatBackground({
    super.key,
    required this.imageUrl,
    required this.blur,
    required this.mediaVisibility,
    required this.scrollController,
  });

  /// How strongly the image shows through once fully faded in.
  static const double imageOpacity = 0.25;

  @override
  State<ActivityChatBackground> createState() => _ActivityChatBackgroundState();
}

class _ActivityChatBackgroundState extends State<ActivityChatBackground> {
  /// The carousel's visible share, null until the timeline first lays out. An
  /// unknown position counts as on screen, so the image doesn't flash in
  /// before the chat appears.
  final ValueNotifier<double?> _mediaVisibleFraction = ValueNotifier(null);

  late Listenable _positionChanges;
  bool _measureScheduled = false;

  bool _enabled = AppSettings.activityImageAsChatBackground.value;

  @override
  void initState() {
    super.initState();
    _listen();
    AppSettings.changes.addListener(_onSettingsChanged);
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(ActivityChatBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaVisibility != widget.mediaVisibility ||
        oldWidget.scrollController != widget.scrollController) {
      _positionChanges.removeListener(_scheduleMeasure);
      _listen();
      _scheduleMeasure();
    }
  }

  @override
  void dispose() {
    AppSettings.changes.removeListener(_onSettingsChanged);
    _positionChanges.removeListener(_scheduleMeasure);
    _mediaVisibleFraction.dispose();
    super.dispose();
  }

  void _listen() {
    _positionChanges = Listenable.merge([
      widget.mediaVisibility,
      widget.scrollController,
    ]);
    _positionChanges.addListener(_scheduleMeasure);
  }

  /// Turning the setting on starts from "unknown" so the image fades in rather
  /// than appearing at full strength.
  void _onSettingsChanged() {
    final enabled = AppSettings.activityImageAsChatBackground.value;
    if (!mounted || enabled == _enabled) return;
    _mediaVisibleFraction.value = null;
    setState(() => _enabled = enabled);
    _scheduleMeasure();
  }

  /// Measures after the frame lays out, since positions read mid-scroll or
  /// mid-build are a frame stale. Runs at most once per frame.
  void _scheduleMeasure() {
    if (!_enabled || _measureScheduled) return;
    _measureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted || !widget.scrollController.hasClients) return;
      _mediaVisibleFraction.value = widget.mediaVisibility.visibleFraction;
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: ValueListenableBuilder(
        valueListenable: _mediaVisibleFraction,
        builder: (context, mediaVisible, child) => AnimatedOpacity(
          opacity: 1.0 - (mediaVisible ?? 1.0),
          duration: FluffyThemes.animationDuration,
          curve: FluffyThemes.animationCurve,
          child: child,
        ),
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Opacity(
            opacity: ActivityChatBackground.imageOpacity,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: widget.blur,
                sigmaY: widget.blur,
              ),
              child: _ActivityBackgroundImage(widget.imageUrl),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityBackgroundImage extends StatelessWidget {
  final Uri imageUrl;

  const _ActivityBackgroundImage(this.imageUrl);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (imageUrl.scheme == 'mxc') {
      return MxcImage(
        uri: imageUrl,
        fit: BoxFit.cover,
        height: size.height,
        width: size.width,
        cacheKey: imageUrl.toString(),
        isThumbnail: false,
      );
    }
    return Image.network(
      imageUrl.toString(),
      excludeFromSemantics: true,
      fit: BoxFit.cover,
      height: size.height,
      width: size.width,
      headers: ImageByUrl.requestHeaders(imageUrl),
      // silent-ok: decorative; the carousel at the top of the chat shows the
      // same image and its own failure state.
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }
}
