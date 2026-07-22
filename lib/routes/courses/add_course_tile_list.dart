import 'package:flutter/material.dart';

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
        return AddCourseTile(
          content: content[index],
          onTap: () => onTap(index),
        );
      },
    );
  }
}
