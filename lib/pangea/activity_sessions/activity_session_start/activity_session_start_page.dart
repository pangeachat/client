import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/activity_sessions/activity_session_start/activity_sessions_start_view.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';

class ActivitySessionStartPage extends StatefulWidget {
  final Room room;
  const ActivitySessionStartPage({
    super.key,
    required this.room,
  });

  @override
  ActivitySessionStartController createState() =>
      ActivitySessionStartController();
}

class ActivitySessionStartController extends State<ActivitySessionStartPage> {
  bool showInstructions = false;

  void toggleInstructions() {
    setState(() {
      showInstructions = !showInstructions;
    });
  }

  Room get room => widget.room;

  String get displayname => widget.room.getLocalizedDisplayname(
        MatrixLocals(L10n.of(context)),
      );

  String get descriptionText => "Let's go";
  String get buttonText => L10n.of(context).start;

  @override
  Widget build(BuildContext context) => ActivitySessionStartView(this);
}
