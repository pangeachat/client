import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/activity_sessions/activity_rating_repo.dart';
import 'package:fluffychat/features/activity_sessions/activity_rating_request.dart';
import 'package:fluffychat/features/activity_sessions/activity_rating_store.dart';
import 'package:fluffychat/features/activity_sessions/activity_roles_room_extension.dart';
import 'package:fluffychat/features/activity_sessions/activity_room_extension.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';

/// Post-play rating prompt, pinned to the bottom of a finished activity chat
/// (issue #7194): thumbs up/down, an optional comment, submit, and a
/// dismiss X.
///
/// Visibility contract (Ava's design): appears once the learner's own role is
/// finished ("I'm done" or an admin's "End for all"), disappears for good
/// after a submitted rating (per pinned version — a session on a NEWER version
/// re-prompts and the server upserts the opinion), and an X dismisses it for
/// this view only, so it returns on reopening the finished, unrated chat.
class ActivityRatingCard extends StatefulWidget {
  final Room room;

  const ActivityRatingCard({super.key, required this.room});

  @override
  State<ActivityRatingCard> createState() => ActivityRatingCardState();
}

@visibleForTesting
class ActivityRatingCardState extends State<ActivityRatingCard> {
  final TextEditingController commentController = TextEditingController();

  ActivityRatingValue? selectedRating;
  bool dismissed = false;
  bool submitting = false;
  bool submitted = false;

  String? errorMessage;

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final activityId = widget.room.activityId;
    if (activityId == null || selectedRating == null || submitting) return;

    setState(() {
      submitting = true;
      errorMessage = null;
    });

    final comment = commentController.text.trim();
    try {
      await ActivityRatingRepo.submitRating(
        ActivityRatingRequest(
          activityId: activityId,
          rating: selectedRating!,
          comment: comment.isEmpty ? null : comment,
          versionStamp: widget.room.pinnedActivityVersionId,
        ),
      );
      await ActivityRatingStore.markRated(
        activityId,
        widget.room.pinnedActivityVersionId,
      );
      if (mounted) setState(() => submitted = true);
    } on ActivityCommentRejectedException {
      // The rating was NOT recorded; keep the card open to reword or clear
      // the comment.
      if (mounted) {
        setState(() {
          errorMessage = L10n.of(context).rateActivityCommentRejected;
        });
      }
    } on ActivitySelfRatingException {
      // Owners can't rate their own activity — record locally so the prompt
      // stops reappearing, and hide quietly.
      await ActivityRatingStore.markRated(
        activityId,
        widget.room.pinnedActivityVersionId,
      );
      if (mounted) setState(() {});
    } catch (e, s) {
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {"roomID": widget.room.id, "activityId": activityId},
      );
      if (mounted) {
        setState(() {
          errorMessage = L10n.of(context).oopsSomethingWentWrong;
        });
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  bool get _visible {
    final activityId = widget.room.activityId;
    return widget.room.hasCompletedRole &&
        activityId != null &&
        !dismissed &&
        (submitted ||
            !ActivityRatingStore.hasRated(
              activityId,
              widget.room.pinnedActivityVersionId,
            ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return AnimatedSize(
      alignment: Alignment.bottomCenter,
      duration: FluffyThemes.animationDuration,
      child: !_visible
          ? const SizedBox.shrink()
          : Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: submitted
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            l10n.rateActivityThanks,
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8.0,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.rateActivityTitle,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                                _RatingThumb(
                                  rating: ActivityRatingValue.up,
                                  selected:
                                      selectedRating == ActivityRatingValue.up,
                                  onTap: () => setState(
                                    () =>
                                        selectedRating = ActivityRatingValue.up,
                                  ),
                                ),
                                _RatingThumb(
                                  rating: ActivityRatingValue.down,
                                  selected:
                                      selectedRating ==
                                      ActivityRatingValue.down,
                                  onTap: () => setState(
                                    () => selectedRating =
                                        ActivityRatingValue.down,
                                  ),
                                ),
                                IconButton(
                                  tooltip: l10n.close,
                                  icon: const Icon(Icons.close, size: 20.0),
                                  onPressed: () =>
                                      setState(() => dismissed = true),
                                ),
                              ],
                            ),
                            TextField(
                              controller: commentController,
                              minLines: 1,
                              maxLines: 3,
                              maxLength: 2000,
                              decoration: InputDecoration(
                                hintText: l10n.rateActivityCommentHint,
                                counterText: "",
                                isDense: true,
                              ),
                            ),
                            if (errorMessage != null)
                              Text(
                                errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ElevatedButton(
                              onPressed: selectedRating == null || submitting
                                  ? null
                                  : submit,
                              child: submitting
                                  ? const SizedBox(
                                      height: 20.0,
                                      width: 20.0,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.0,
                                      ),
                                    )
                                  : Text(l10n.submit),
                            ),
                          ],
                        ),
                ),
              ),
            ),
    );
  }
}

class _RatingThumb extends StatelessWidget {
  final ActivityRatingValue rating;
  final bool selected;
  final VoidCallback onTap;

  const _RatingThumb({
    required this.rating,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final up = rating == ActivityRatingValue.up;
    return IconButton(
      tooltip: up ? L10n.of(context).yes : L10n.of(context).no,
      icon: Icon(
        selected
            ? (up ? Icons.thumb_up : Icons.thumb_down)
            : (up ? Icons.thumb_up_outlined : Icons.thumb_down_outlined),
        color: selected ? theme.colorScheme.primary : null,
      ),
      onPressed: onTap,
    );
  }
}
