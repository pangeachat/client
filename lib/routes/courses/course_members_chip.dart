import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_info_chip_widget.dart';

/// A course's member count, voiced as "N participants" rather than the bare
/// number the chip draws.
class CourseMembersChip extends StatelessWidget {
  final int members;

  final double? fontSize;
  final double? iconSize;
  final EdgeInsets? padding;

  const CourseMembersChip(
    this.members, {
    super.key,
    required this.fontSize,
    required this.iconSize,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: L10n.of(context).countParticipants(members),
      child: ExcludeSemantics(
        child: CourseInfoChip(
          icon: Icons.group,
          text: '$members',
          fontSize: fontSize,
          iconSize: iconSize,
          padding: padding,
        ),
      ),
    );
  }
}
