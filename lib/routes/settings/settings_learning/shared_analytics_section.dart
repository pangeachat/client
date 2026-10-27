import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/analytics_access/analytics_sharing_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The courses whose teachers can see the learner's progress, which the
/// snackbar on joining a course links to. Read-only: leaving a course stops
/// the sharing (course-analytics-access.instructions.md).
class SharedAnalyticsSection extends StatefulWidget {
  const SharedAnalyticsSection({super.key});

  @override
  State<SharedAnalyticsSection> createState() => _SharedAnalyticsSectionState();
}

class _SharedAnalyticsSectionState extends State<SharedAnalyticsSection> {
  late final Future<List<Room>> _courses = _load();

  Future<List<Room>> _load() async {
    try {
      return await Matrix.of(context).client.coursesSharingAnalytics();
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {},
        level: PangeaHttpException.severityOf(e),
      );
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Column(
      children: [
        ListTile(
          title: Text(
            l10n.sharedAnalyticsTitle,
            style: TextStyle(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(l10n.sharedAnalyticsDesc),
        ),
        FutureBuilder<List<Room>>(
          future: _courses,
          builder: (context, snapshot) {
            // A failed read shows nothing rather than an empty list, which
            // would claim the learner shares with no course.
            if (snapshot.hasError) return const SizedBox.shrink();
            final courses = snapshot.data;
            if (courses == null) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator.adaptive(),
              );
            }
            if (courses.isEmpty) {
              return ListTile(subtitle: Text(l10n.sharedAnalyticsNone));
            }
            return Column(
              children: [
                for (final course in courses)
                  ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: Text(
                      course.getLocalizedDisplayname(MatrixLocals(l10n)),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
