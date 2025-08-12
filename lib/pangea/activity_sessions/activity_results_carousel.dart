import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_role_model.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_response_model.dart';

class ActivityResultsCarousel extends StatelessWidget {
  final ActivityRoleModel selectedRole;
  final ParticipantSummaryModel summary;

  final User? user;

  const ActivityResultsCarousel({
    super.key,
    required this.selectedRole,
    required this.summary,
    this.user,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24.0),
      ),
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.feedback,
            style: const TextStyle(fontSize: 12.0),
          ),
          const SizedBox(height: 10.0),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              Container(
                padding: const EdgeInsets.all(4.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  spacing: 4.0,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school, size: 12.0),
                    Text(
                      summary.cefrLevel,
                      style: const TextStyle(
                        fontSize: 12.0,
                      ),
                    ),
                  ],
                ),
              ),
              ...summary.superlatives.map(
                (sup) => Container(
                  padding: const EdgeInsets.all(4.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    sup,
                    style: const TextStyle(
                      fontSize: 12.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
