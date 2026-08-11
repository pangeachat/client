import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/spaces/knocking_users_builder.dart';
import 'package:fluffychat/routes/courses/add_course_tile.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';

class AddCourseTileList extends StatelessWidget {
  final List<AddCourseTileContent> content;
  final void Function(int) onTap;

  final List<Widget>? extraContent;
  final ScrollController? controller;
  final double spacing;

  const AddCourseTileList({
    super.key,
    required this.content,
    required this.onTap,
    this.extraContent,
    this.controller,
    this.spacing = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = content.length + (extraContent?.length ?? 0);
    return ListView.separated(
      controller: controller,
      separatorBuilder: (_, _) => SizedBox(height: spacing),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= content.length) {
          final adjustedIndex = index - content.length;
          return extraContent?[adjustedIndex] ?? SizedBox.shrink();
        }
        // Mobile has no nav rail, so the courses list is where an admin sees
        // that someone is knocking — the same red "!" the rail's course avatar
        // wears (#8246). Only room-backed tiles can have a knock; previews and
        // course-plan suggestions skip the member request entirely.
        final tileContent = content[index];
        final space = tileContent.space;
        if (space == null) {
          return AddCourseTile(content: tileContent, onTap: () => onTap(index));
        }

        return KnockingUsersBuilder(
          room: space,
          builder: (context, knockingUsers) => AddCourseTile(
            content: tileContent,
            onTap: () => onTap(index),
            hasKnockingUsers: knockingUsers.isNotEmpty,
          ),
        );
      },
    );
  }
}
