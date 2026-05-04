import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/activity_sessions/activity_summary_room_extension.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_model.dart';
import 'package:fluffychat/pangea/activity_summary/activity_summary_response_model.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LoadActivitySummaryWidget extends StatefulWidget {
  final Room room;
  const LoadActivitySummaryWidget({super.key, required this.room});

  @override
  State<LoadActivitySummaryWidget> createState() =>
      LoadActivitySummaryWidgetState();
}

class LoadActivitySummaryWidgetState extends State<LoadActivitySummaryWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadActivitySummary();
    });
  }

  ActivitySummaryModel? get _summaryEvent => widget.room.activitySummaryByL1;

  ActivitySummaryResponseModel? get _summary => _summaryEvent?.summary;

  Future<void> _fetchActivitySummary() async {
    final l1 = MatrixState.pangeaController.userController.userL1Code;
    if (l1 == null) {
      ErrorHandler.logError(
        e: "Tried to request activity summary with null l1Code",
        data: {},
      );
      return;
    }
    await widget.room.fetchSummaries(l1);
  }

  Future<void> _loadActivitySummary() async {
    if (_summary != null) return;

    // The summary state event is null
    // Wait for 5 seconds. If still null (or not loading), run request.
    if (_summaryEvent == null) {
      await _fetchActivitySummary();
      return;
    }

    // The summary state event is waiting (<= 10 seconds since request)
    // Wait for 10 seconds (or time remaining until not waiting). If summary still not there, run request.
    if (_summaryEvent!.isLoading) {
      final remainingTime = DateTime.now()
          .difference(_summaryEvent!.requestedAt!)
          .inSeconds;

      await Future.delayed(
        Duration(seconds: remainingTime < 10 ? 10 - remainingTime : 0),
        () async {
          if (_summary == null) await _fetchActivitySummary();
        },
      );
      return;
    }

    if (_summaryEvent!.errorAt == null) {
      await _fetchActivitySummary();
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
