import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/home/join_course_badge.dart';

/// The seat invitation card on the sign-up and login pages (SPEC §4 Student
/// 3): the course name and masked invited address from the public hint, so
/// the student signs in with the invited address. Nothing is sent from here;
/// the invitation is opened after sign-in.
///
/// An invitation the module no longer knows (withdrawn, used) is dropped,
/// and [fallback] (the class code card) shows instead: the class code still
/// joins.
class InvitationNotice extends StatefulWidget {
  final PendingInvitation pending;
  final StudentInvitationApi? api;
  final Widget fallback;

  const InvitationNotice({
    super.key,
    required this.pending,
    this.api,
    this.fallback = const SizedBox.shrink(),
  });

  @override
  State<InvitationNotice> createState() => _InvitationNoticeState();
}

class _InvitationNoticeState extends State<InvitationNotice> {
  late final StudentInvitationApi _api =
      widget.api ??
      StudentInvitationApi(
        httpClient: http.Client(),
        homeserver: Uri.parse(AppConfig.defaultHomeserver),
      );

  InvitationHint? _hint;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _loadHint();
  }

  Future<void> _loadHint() async {
    try {
      final hint = await _api.hint(widget.pending.invitationId);
      if (mounted) setState(() => _hint = hint);
    } on StudentInvitationApiException catch (e) {
      if (e.statusCode != 404) {
        _keepWithoutHint();
        return;
      }
      await SpaceCodeRepo.clearPendingInvitation();
      if (mounted) setState(() => _gone = true);
    } catch (_) {
      _keepWithoutHint();
    }
  }

  // silent-ok: the hint only names the course; without it the card still
  // shows, and the open after sign-in decides.
  void _keepWithoutHint() {
    if (mounted) setState(() => _hint = const InvitationHint());
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return widget.fallback;
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final hint = _hint;
    final masked = hint?.maskedEmailHint;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          spacing: 12.0,
          children: [
            const JoinCourseBadge(size: 40.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2.0,
                children: [
                  Text(
                    l10n.seatInviteTitle(
                      hint?.courseName ?? l10n.seatInviteYourCourse,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (masked != null)
                    Text(
                      l10n.seatInviteEmailHint(masked),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
