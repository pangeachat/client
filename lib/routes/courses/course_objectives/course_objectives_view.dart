import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_room_extension.dart';
import 'package:fluffychat/features/navigation/route_paths.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_objectives/course_objectives_repo.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';

/// Left-column outline for a joined course (world_v2): the course's
/// learning objectives grouped by the location their activities sit at.
/// City labels come from the activity map data, not a nested topic field.
/// Tapping an objective opens the activity as a first-class world object.
class CourseObjectivesView extends StatefulWidget {
  final Room space;
  const CourseObjectivesView({required this.space, super.key});

  @override
  State<CourseObjectivesView> createState() => _CourseObjectivesViewState();
}

class _CourseObjectivesViewState extends State<CourseObjectivesView> {
  late Future<List<CourseLocationGroup>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _load();
  }

  @override
  void didUpdateWidget(covariant CourseObjectivesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.space.id != widget.space.id) {
      _groupsFuture = _load();
    }
  }

  Future<List<CourseLocationGroup>> _load() async {
    final coursePlanId = widget.space.coursePlan?.uuid;
    if (coursePlanId == null) return [];
    return CourseObjectivesRepo.forCoursePlan(coursePlanId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.space.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: L10n.of(context).chat,
            icon: const Icon(Icons.forum_outlined),
            onPressed: () =>
                context.go('${PRoutes.course(widget.space.id)}/details'),
          ),
        ],
      ),
      body: FutureBuilder<List<CourseLocationGroup>>(
        future: _groupsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          final groups = snapshot.data ?? const [];
          if (groups.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  L10n.of(context).noActivitiesFound,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: groups.length,
            itemBuilder: (context, i) => _LocationSection(group: groups[i]),
          );
        },
      ),
    );
  }
}

class _LocationSection extends StatelessWidget {
  final CourseLocationGroup group;
  const _LocationSection({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // Keep the section open by default; this is an outline, not a drawer.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        leading: const Icon(Icons.location_on_outlined),
        title: Text(
          group.locationName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          L10n.of(context).numObjectives(group.objectives.length),
        ),
        childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
        children: [
          for (final item in group.objectives)
            ListTile(
              dense: true,
              leading: const Icon(Icons.flag_outlined, size: 20),
              title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                item.objective,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.colorScheme.outline),
              ),
              onTap: () => context.go(PRoutes.worldObject(item.activityId)),
            ),
        ],
      ),
    );
  }
}
