import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluffychat/features/activity_sessions/activity_plan_model.dart';
import 'package:fluffychat/features/activity_sessions/activity_plan_repo.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/world/world_view_items.dart';
import 'package:fluffychat/routes/world/world_view_markers.dart';

/// The two cards the world view opens on a tap (org world-view doc): a
/// city's, a carousel of the activities at that city, and a ship's, what the
/// course is and who is in it. Both stand on their point with a caret, like
/// the teacher dashboard's planner card and the map's activity card.
class WorldViewCardFrame extends StatelessWidget {
  static const double width = 272;
  static const double height = 296;
  static const double tailHeight = 10;
  static const double radius = 14;

  final Widget child;
  final String closeLabel;
  final VoidCallback onDismiss;
  const WorldViewCardFrame({
    super.key,
    required this.child,
    required this.closeLabel,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frame = theme.colorScheme.primary;
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: frame, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 12),
                    ],
                  ),
                  child: child,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Semantics(
                    button: true,
                    label: closeLabel,
                    child: InkWell(
                      onTap: onDismiss,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          CustomPaint(
            size: const Size(22, tailHeight),
            painter: _TailPainter(frame),
          ),
        ],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  final Color color;
  _TailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color;
}

/// A city's card: its name and how many activities are there, a carousel of
/// those activities (each slide an activity's picture and title, turning
/// every five seconds while nobody points at it), and Explore, which brings
/// the map down into the city. Tapping a slide opens that activity.
/// Where a city card reads its slides' plans: the repo's cache, then the repo.
class CityCardPlans {
  const CityCardPlans();

  ActivityPlanModel? cached(String activityId) =>
      ActivityPlanRepo.instance.cachedPlan(activityId);

  Future<ActivityPlanModel?> read(String activityId) =>
      ActivityPlanRepo.instance.getPlan(activityId);
}

class WorldCityCard extends StatefulWidget {
  final WorldCity city;

  /// The activities at the city, from the Missions placed there across the
  /// learner's courses and the public catalog's ([activityIdsAtCity]).
  final List<String> activityIds;
  final VoidCallback onExplore;
  final void Function(String activityId) onOpenActivity;
  final VoidCallback onDismiss;
  final CityCardPlans plans;

  const WorldCityCard({
    super.key,
    required this.city,
    required this.activityIds,
    required this.onExplore,
    required this.onOpenActivity,
    required this.onDismiss,
    this.plans = const CityCardPlans(),
  });

  @override
  State<WorldCityCard> createState() => _WorldCityCardState();
}

class _WorldCityCardState extends State<WorldCityCard> {
  static const _turn = Duration(seconds: 5);
  final Map<String, ActivityPlanModel> _plans = {};
  final Set<String> _failed = {};
  final Set<String> _requested = {};
  int _index = 0;
  bool _hovering = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _hydrate();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant WorldCityCard old) {
    super.didUpdateWidget(old);
    if (old.city.key != widget.city.key) {
      _plans.clear();
      _failed.clear();
      _requested.clear();
      _index = 0;
      _hydrate();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The plans for the slide on show and the next one, for their picture and
  /// title: the carousel shows one at a time, so a city with forty activities
  /// reads two, and the rest as it turns. A plan that cannot be read is
  /// reported by the repo and its slide is skipped, never shown broken.
  void _hydrate() {
    final slides = _slides;
    for (var offset = 0; offset < min(2, slides.length); offset++) {
      final id = slides[(_index + offset) % slides.length];
      if (_plans.containsKey(id) || !_requested.add(id)) continue;
      final cached = widget.plans.cached(id);
      if (cached != null) {
        _plans[id] = cached;
        continue;
      }
      widget.plans.read(id).then((plan) {
        if (!mounted) return;
        setState(() {
          if (plan == null) {
            _failed.add(id);
          } else {
            _plans[id] = plan;
          }
        });
        // A skipped slide moves the next one up; it may not be read yet.
        if (plan == null) _hydrate();
      });
    }
  }

  List<String> get _slides => [
    for (final id in widget.activityIds)
      if (!_failed.contains(id)) id,
  ];

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_turn, () {
      if (!mounted) return;
      final count = _slides.length;
      final reduced = MediaQuery.of(context).disableAnimations;
      if (count > 1 && !_hovering && !reduced) {
        setState(() => _index = (_index + 1) % count);
        _hydrate();
      }
      _schedule();
    });
  }

  void _step(int by) {
    final count = _slides.length;
    if (count == 0) return;
    setState(() => _index = (_index + by + count) % count);
    _hydrate();
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final slides = _slides;
    final count = slides.length;
    final at = count == 0 ? 0 : _index % count;
    final id = count == 0 ? null : slides[at];
    final plan = id == null ? null : _plans[id];
    return WorldViewCardFrame(
      closeLabel: l10n.worldCardClose(widget.city.name),
      onDismiss: widget.onDismiss,
      child: MouseRegion(
        onEnter: (_) => _hovering = true,
        onExit: (_) => _hovering = false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 132,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (plan?.imageURL != null)
                    GestureDetector(
                      onTap: () => widget.onOpenActivity(id!),
                      child: CachedNetworkImage(
                        imageUrl: plan!.imageURL.toString(),
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _Placeholder(theme: theme),
                      ),
                    )
                  else
                    _Placeholder(theme: theme, loading: id != null),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 18, 10, 6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.city.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            l10n.numActivities(widget.activityIds.length),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Semantics(
                        label: count == 0
                            ? null
                            : l10n.worldCardSlide(at + 1, count),
                        child: Text(
                          count == 0
                              ? l10n.worldCityNothingHere
                              : (plan?.title ?? l10n.loadingPleaseWait),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    Row(
                      spacing: 4,
                      children: [
                        if (count > 1)
                          _Chevron(
                            icon: Icons.chevron_left,
                            label: l10n.worldCardPrevious,
                            onTap: () => _step(-1),
                          ),
                        Expanded(
                          child: FilledButton(
                            onPressed: widget.onExplore,
                            child: Text(l10n.worldExploreCity),
                          ),
                        ),
                        if (count > 1)
                          _Chevron(
                            icon: Icons.chevron_right,
                            label: l10n.worldCardNext,
                            onTap: () => _step(1),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (count > 1) _Dots(count: count, at: at, onPick: _pick),
          ],
        ),
      ),
    );
  }

  void _pick(int i) {
    setState(() => _index = i);
    _schedule();
  }
}

class _Placeholder extends StatelessWidget {
  final ThemeData theme;
  final bool loading;
  const _Placeholder({required this.theme, this.loading = false});

  @override
  Widget build(BuildContext context) => Container(
    color: theme.colorScheme.surfaceContainerHighest,
    alignment: Alignment.center,
    child: loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            Icons.explore_outlined,
            size: 28,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
  );
}

class _Chevron extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Chevron({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: label,
    icon: Icon(icon),
    visualDensity: VisualDensity.compact,
  );
}

class _Dots extends StatelessWidget {
  static const int maxDots = 10;
  final int count;
  final int at;
  final void Function(int) onPick;
  const _Dots({required this.count, required this.at, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: count > maxDots
          ? Text(
              '${at + 1} / $count',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                for (var i = 0; i < count; i++)
                  GestureDetector(
                    onTap: () => onPick(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: i == at ? 12 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == at
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// What a ship's card says about its course: its name, the city it is at,
/// who runs it (its human admins; Pangea for a central course), how many
/// people are in it, and what the course says it is. An affiliated
/// institution shows once the course record carries one; today none does.
class WorldShipInfo {
  final String name;
  final String cityName;
  final List<String> admins;
  final bool central;
  final int? members;
  final String? description;
  final bool aboard;

  /// Whether a learner may join outright (`public`) or must ask (`knock`).
  final bool joinOutright;

  const WorldShipInfo({
    required this.name,
    required this.cityName,
    required this.admins,
    required this.central,
    required this.members,
    required this.description,
    required this.aboard,
    required this.joinOutright,
  });
}

class WorldShipCard extends StatelessWidget {
  final WorldShipInfo info;

  /// Open the course (aboard) or its preview to join (public).
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  const WorldShipCard({
    super.key,
    required this.info,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final runBy = info.central
        ? l10n.worldShipRunByPangea
        : info.admins.isEmpty
        ? null
        : l10n.worldShipRunBy(info.admins.join(', '));
    return WorldViewCardFrame(
      closeLabel: l10n.worldCardClose(info.name),
      onDismiss: onDismiss,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: 8,
              children: [
                AirshipIcon(size: 24, color: theme.colorScheme.primary),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: Text(
                      info.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _InfoLine(
              icon: Icons.location_on_outlined,
              text: l10n.worldShipAtCity(info.cityName),
            ),
            if (runBy != null)
              _InfoLine(icon: Icons.person_outline, text: runBy),
            if (info.members != null)
              _InfoLine(
                icon: Icons.group_outlined,
                text: l10n.worldShipMembers(info.members!),
              ),
            if (info.description case final description?
                when description.trim().isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    description,
                    overflow: TextOverflow.fade,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              )
            else
              const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onOpen,
                child: Text(
                  info.aboard
                      ? l10n.worldShipOpenCourse
                      : info.joinOutright
                      ? l10n.join
                      : l10n.askToJoin,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        spacing: 6,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
