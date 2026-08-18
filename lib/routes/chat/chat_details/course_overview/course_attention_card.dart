import 'package:flutter/material.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';

/// The gold attention card the course page opens with: [icon] and [title]
/// over a bulk action, then [rows] capped at [_maxCollapsedRows] behind a
/// load-more expander so a pile of them never overwhelms the page.
///
/// The shell behind both attention cards — pending join requests
/// (`CourseKnockRequests`) and everything else (`CourseCatchUp`) — which
/// differ only in their icon, title, action and rows. Renders nothing when
/// [rows] is empty, so each caller can hand over whatever it has.
class CourseAttentionCard extends StatefulWidget {
  final Widget icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final List<Widget> rows;

  const CourseAttentionCard({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    required this.rows,
    super.key,
  });

  @override
  State<CourseAttentionCard> createState() => _CourseAttentionCardState();
}

class _CourseAttentionCardState extends State<CourseAttentionCard> {
  static const int _maxCollapsedRows = 2;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final visible = _expanded ? rows : rows.take(_maxCollapsedRows).toList();
    final hiddenCount = rows.length - visible.length;
    return Semantics(
      label: widget.title,
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: AppConfig.goldByTheme(context).withAlpha(30),
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The title wraps rather than ellipsizes, and the action can fall
            // to a second line: these titles are full sentences in some
            // languages, and the card sits in a panel as narrow as a phone
            // (#8462).
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.icon,
                    const SizedBox(width: 10.0),
                    Flexible(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: widget.onAction,
                  child: Text(
                    widget.actionLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4.0),
            ...visible,
            if (hiddenCount > 0)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _expanded = true),
                  child: Text(
                    L10n.of(context).loadMore,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
