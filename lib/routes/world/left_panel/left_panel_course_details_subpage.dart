import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/features/navigation/token_params/course_details_token.dart';
import 'package:fluffychat/features/navigation/workspace_nav.dart';
import 'package:fluffychat/features/tutorials/tutorial_target.dart';
import 'package:fluffychat/features/tutorials/tutorial_target_ids.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/chat_details/chat_details.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LeftPanelCourseDetailsSubpage extends StatefulWidget {
  final CourseDetailsTokenParam? param;
  final String? spaceId;
  final Widget closeButton;

  const LeftPanelCourseDetailsSubpage({
    super.key,
    required this.param,
    required this.spaceId,
    required this.closeButton,
  });

  @override
  State<LeftPanelCourseDetailsSubpage> createState() =>
      _LeftPanelCourseDetailsSubpageState();
}

class _LeftPanelCourseDetailsSubpageState
    extends State<LeftPanelCourseDetailsSubpage> {
  /// The course id last resolved against the complete room list, so a rebuild
  /// never restarts the wait or replaces the token twice.
  String? _resolvedSpaceId;

  /// Cancelled on dispose: a wait for the first sync must not outlive the
  /// panel.
  StreamSubscription<SyncUpdate>? _firstSync;

  /// A course the learner is not in has no card. Once the room list is
  /// complete — loaded from the store, and past the first sync on a fresh
  /// login — a course still missing from it is not held, and its token is
  /// replaced in place by the course's preview, where the learner can join
  /// (routing.instructions.md § The course context, #9586).
  Future<void> _resolve(Client client, String spaceId) async {
    _resolvedSpaceId = spaceId;
    await client.roomsLoading;
    if (!mounted) return;
    if (client.prevBatch != null) {
      _decide(client, spaceId);
      return;
    }
    _firstSync?.cancel();
    _firstSync = client.onSync.stream.listen((_) {
      _firstSync?.cancel();
      _firstSync = null;
      _decide(client, spaceId);
    });
  }

  void _decide(Client client, String spaceId) {
    if (!mounted || widget.spaceId != spaceId) return;
    if (client.getRoomById(spaceId) != null) {
      setState(() {});
      return;
    }
    final router = GoRouter.of(context);
    router.replace(
      WorkspaceNav.openCoursePreview(
        router.routeInformationProvider.value.uri,
        spaceId,
      ),
    );
  }

  @override
  void dispose() {
    _firstSync?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spaceId = widget.spaceId;
    if (spaceId == null) return const SizedBox.shrink();

    final client = Matrix.of(context).client;
    if (client.getRoomById(spaceId) == null) {
      if (_resolvedSpaceId != spaceId) _resolve(client, spaceId);
      return Scaffold(
        appBar: AppBar(leading: widget.closeButton),
        body: Center(
          child: CircularProgressIndicator.adaptive(
            semanticsLabel: L10n.of(context).loadingPleaseWait,
          ),
        ),
      );
    }

    // Registered here rather than inside ChatDetails: this is the one place a
    // `course` token is rendered, so the id has a single claimant, and the rect
    // is the whole panel — header, close control and plan sections — which is
    // what the course tutorial's first step lights.
    return TutorialTarget(
      targetId: TutorialTargetIds.coursePanel,
      child: ChatDetails(
        roomId: spaceId,
        activeTab: widget.param?.activeTab,
        expandedSection: widget.param?.expanded ?? false,
        embeddedCloseButton: widget.closeButton,
      ),
    );
  }
}
