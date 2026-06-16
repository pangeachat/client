import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/analytics/client_analytics_extension.dart';
import 'package:fluffychat/features/analytics/construct_type_enum.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/analytics_data/derived_analytics_data_model.dart';
import 'package:fluffychat/features/navigation/route_facts.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/widgets/analytics_summary/progress_indicators_enum.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The persistent top-right cluster over the world map (world_v2): the user's
/// avatar wrapped in a circular XP ring with a gold level badge and L2 flag,
/// plus a vertical pill of three tappable trackers — completed Sessions (top),
/// Grammar (middle), Vocabulary (bottom). Tapping a tracker opens that metric's
/// analytics docked on the right (`?analytics=<tab>`); the avatar opens
/// `/profile`. All data is already client-side (see
/// `world-user-cluster.instructions.md`); the cluster listens to the analytics
/// update streams so counts/level/XP stay live.
class WorldUserCluster extends StatefulWidget {
  const WorldUserCluster({super.key});

  @override
  State<WorldUserCluster> createState() => _WorldUserClusterState();
}

class _WorldUserClusterState extends State<WorldUserCluster> {
  StreamSubscription<dynamic>? _constructSub;
  StreamSubscription<dynamic>? _activitySub;
  bool _wired = false;

  int _level = 1;
  double _progress = 0.0;
  int _vocab = 0;
  int _grammar = 0;
  int _sessions = 0;

  Uri? _avatarUrl;
  String? _displayName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final dispatcher =
        Matrix.of(context).analyticsDataService.updateDispatcher;
    _constructSub = dispatcher.constructUpdateStream.stream.listen(
      (_) => _refresh(),
    );
    _activitySub = dispatcher.activityAnalyticsStream.stream.listen(
      (_) => _refresh(),
    );
    _loadProfile();
    _refresh();
  }

  @override
  void dispose() {
    _constructSub?.cancel();
    _activitySub?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await Matrix.of(context).client.fetchOwnProfile();
      if (!mounted) return;
      setState(() {
        _avatarUrl = profile.avatarUrl;
        _displayName = profile.displayName;
      });
    } catch (_) {
      // Avatar falls back to the initial; not worth surfacing.
    }
  }

  Future<void> _refresh() async {
    final service = Matrix.of(context).analyticsDataService;
    final client = Matrix.of(context).client;
    final l2 = MatrixState.pangeaController.userController.userL2;
    if (l2 == null) return;
    if (service.isInitializing) {
      try {
        await service.initCompleter.future;
      } catch (_) {}
    }
    if (!mounted) return;
    DerivedAnalyticsDataModel? derived;
    try {
      derived = await service.derivedData(l2.langCodeShort);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _level = derived?.level ?? _level;
      _progress = (derived?.levelProgress ?? _progress).clamp(0.0, 1.0);
      _vocab = service.numConstructs(ConstructTypeEnum.vocab);
      _grammar = service.numConstructs(ConstructTypeEnum.morph);
      // Use the same filtered accessor the sessions panel (ActivityArchive)
      // renders — `archivedActivities` drops uncached + left/banned rooms — so
      // the badge count always matches the list the panel shows.
      _sessions =
          client.ownAnalyticsRoomLocalByL2?.archivedActivities.length ?? 0;
    });
  }

  /// Open the right-docked analytics panel over the current route, preserving
  /// every other param (mirrors the `?activity=` open). Drops any open detail
  /// (`?construct`) so switching trackers always lands on the new tab's summary
  /// — a leftover construct could otherwise render under a mismatched tab.
  void _openAnalytics(AnalyticsPanelTab tab) {
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    final params = Map<String, String>.from(uri.queryParameters)
      ..['analytics'] = tab.queryValue
      ..remove('construct');
    context.go(uri.replace(queryParameters: params).toString());
  }

  void _openProfile() => context.go(PRoutes.profile);

  @override
  Widget build(BuildContext context) {
    final l2 = MatrixState.pangeaController.userController.userL2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _LeveledAvatar(
          level: _level,
          progress: _progress,
          avatarUrl: _avatarUrl,
          name: _displayName,
          flagEmoji: l2?.localeEmoji,
          onTap: _openProfile,
        ),
        const SizedBox(height: 8),
        _TrackerPill(
          sessions: _sessions,
          grammar: _grammar,
          vocab: _vocab,
          onTap: _openAnalytics,
        ),
      ],
    );
  }
}

/// Circular avatar + gold XP ring + level badge + L2 flag badge.
class _LeveledAvatar extends StatelessWidget {
  final int level;
  final double progress;
  final Uri? avatarUrl;
  final String? name;
  final String? flagEmoji;
  final VoidCallback onTap;

  const _LeveledAvatar({
    required this.level,
    required this.progress,
    required this.avatarUrl,
    required this.name,
    required this.flagEmoji,
    required this.onTap,
  });

  static const double _avatarSize = 56.0;
  static const double _stroke = 4.0;
  static const double _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const ringDiameter = _avatarSize + 2 * (_stroke + _gap);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: ringDiameter,
          height: ringDiameter + 6,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              SizedBox(
                width: ringDiameter,
                height: ringDiameter,
                child: CustomPaint(
                  painter: _XpRingPainter(
                    progress: progress,
                    trackColor: AppConfig.goldLight.withValues(alpha: 0.35),
                    progressColor: AppConfig.gold,
                    stroke: _stroke,
                  ),
                ),
              ),
              Positioned(
                top: _stroke + _gap,
                child: Avatar(
                  mxContent: avatarUrl,
                  name: name,
                  size: _avatarSize,
                  onTap: onTap,
                  showPresence: false,
                ),
              ),
              if (flagEmoji != null && flagEmoji!.isNotEmpty)
                Positioned(
                  top: 0,
                  left: 0,
                  child: _Badge(
                    background: theme.colorScheme.surface,
                    child: Text(
                      flagEmoji!,
                      style: const TextStyle(fontSize: 12, height: 1.1),
                    ),
                  ),
                ),
              Positioned(
                bottom: 0,
                child: _Badge(
                  background: AppConfig.gold,
                  child: Text(
                    '$level',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small circular badge (flag or level) with a white outline.
class _Badge extends StatelessWidget {
  final Color background;
  final Widget child;
  const _Badge({required this.background, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: child,
    );
  }
}

class _XpRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double stroke;

  _XpRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    final sweep = progress.clamp(0.0, 1.0) * 2 * math.pi;
    if (sweep <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = progressColor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_XpRingPainter old) =>
      old.progress != progress ||
      old.progressColor != progressColor ||
      old.trackColor != trackColor ||
      old.stroke != stroke;
}

/// Vertical pill of three tappable trackers: Sessions, Grammar, Vocabulary.
class _TrackerPill extends StatelessWidget {
  final int sessions;
  final int grammar;
  final int vocab;
  final void Function(AnalyticsPanelTab) onTap;

  const _TrackerPill({
    required this.sessions,
    required this.grammar,
    required this.vocab,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TrackerButton(
              indicator: ProgressIndicatorEnum.activities,
              count: sessions,
              isFirst: true,
              onTap: () => onTap(AnalyticsPanelTab.sessions),
            ),
            _divider(theme),
            _TrackerButton(
              indicator: ProgressIndicatorEnum.morphsUsed,
              count: grammar,
              onTap: () => onTap(AnalyticsPanelTab.grammar),
            ),
            _divider(theme),
            _TrackerButton(
              indicator: ProgressIndicatorEnum.wordsUsed,
              count: vocab,
              isLast: true,
              onTap: () => onTap(AnalyticsPanelTab.vocab),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(ThemeData theme) => Container(
    height: 1,
    width: 28,
    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
  );
}

class _TrackerButton extends StatelessWidget {
  final ProgressIndicatorEnum indicator;
  final int count;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const _TrackerButton({
    required this.indicator,
    required this.count,
    required this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = Radius.circular(AppConfig.borderRadius);
    return Tooltip(
      message: indicator.tooltip(context),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: isFirst ? radius : Radius.zero,
          bottom: isLast ? radius : Radius.zero,
        ),
        child: Semantics(
          button: true,
          label: '${indicator.tooltip(context)}: $count',
          excludeSemantics: true,
          child: Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  indicator.icon,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 2),
                Text(
                  '$count',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
