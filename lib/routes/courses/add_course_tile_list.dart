import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/spaces/knocking_users_builder.dart';
import 'package:fluffychat/routes/courses/add_course_tile.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';

class AddCourseTileList extends StatelessWidget {
  final List<AddCourseTileContent> content;
  final void Function(int) onTap;

  /// Section headers keyed by the [content] index they sit above, in order.
  /// Several headers can share a key (consecutive collapsed sections), and a
  /// key equal to `content.length` renders after the last tile — a trailing
  /// section whose tiles are all hidden still shows its header (#8425).
  final Map<int, List<Widget>> sectionHeaders;

  final List<Widget>? extraContent;
  final ScrollController? controller;
  final double spacing;

  const AddCourseTileList({
    super.key,
    required this.content,
    required this.onTap,
    this.sectionHeaders = const {},
    this.extraContent,
    this.controller,
    this.spacing = 8.0,
  });

  /// Headers and tiles flattened into one index space, in order.
  List<_ListEntry> get _entries => [
    for (var i = 0; i <= content.length; i++) ...[
      for (final header in sectionHeaders[i] ?? const <Widget>[])
        _ListEntry.header(header),
      if (i < content.length) _ListEntry.tile(i),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final itemCount = entries.length + (extraContent?.length ?? 0);
    return ListView.separated(
      controller: controller,
      separatorBuilder: (_, _) => SizedBox(height: spacing),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= entries.length) {
          final adjustedIndex = index - entries.length;
          return extraContent?[adjustedIndex] ?? SizedBox.shrink();
        }
        final entry = entries[index];
        if (entry.header != null) return entry.header!;

        // Mobile has no nav rail, so the courses list is where an admin sees
        // that someone is knocking — the same red "!" the rail's course avatar
        // wears (#8246). Only room-backed tiles can have a knock; previews and
        // course-plan suggestions skip the member request entirely.
        final contentIndex = entry.contentIndex!;
        final tileContent = content[contentIndex];
        final space = tileContent.space;
        if (space == null) {
          return AddCourseTile(
            content: tileContent,
            onTap: () => onTap(contentIndex),
          );
        }

        return KnockingUsersBuilder(
          room: space,
          builder: (context, knockingUsers) => AddCourseTile(
            content: tileContent,
            onTap: () => onTap(contentIndex),
            hasKnockingUsers: knockingUsers.isNotEmpty,
          ),
        );
      },
    );
  }
}

/// One row of [AddCourseTileList]: either a section header or the tile at
/// [contentIndex].
class _ListEntry {
  final Widget? header;
  final int? contentIndex;

  const _ListEntry.header(Widget this.header) : contentIndex = null;
  const _ListEntry.tile(int this.contentIndex) : header = null;
}
