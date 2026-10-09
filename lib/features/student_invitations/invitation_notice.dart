import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/features/join_codes/space_code_repo.dart';
import 'package:fluffychat/features/student_invitations/managed_consent.dart';
import 'package:fluffychat/features/student_invitations/pending_claims.dart';
import 'package:fluffychat/features/student_invitations/student_invitation_api.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/home/join_course_badge.dart';

/// The seat invitation card on the sign-up and login pages (SPEC §4 Student
/// 3): the course name and masked invited address from the public hint, and
/// the mandatory checkbox with the disclosure under it. Ticking it is kept
/// with the ferried invitation (SpaceCodeRepo.pendingInvitation) and the
/// confirmation is sent after sign-in; nothing is sent from here. Left
/// unticked, the in-app confirmation asks again after sign-in.
///
/// The pages put it in a `Flexible` scroll view, so the disclosure scrolls
/// instead of pushing the sign-in buttons off a short screen.
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

class _InvitationNoticeState extends State<InvitationNotice>
    with ManagedDisclosureLoader {
  late final StudentInvitationApi _api =
      widget.api ??
      StudentInvitationApi(
        httpClient: http.Client(),
        homeserver: Uri.parse(AppConfig.defaultHomeserver),
      );

  InvitationHint? _hint;
  bool _gone = false;
  late bool _checked = widget.pending.ackedDisclosureVersion != null;

  @override
  StudentInvitationApi get disclosureApi => _api;

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
  // shows the checkbox, and the confirmation after sign-in decides.
  void _keepWithoutHint() {
    if (mounted) setState(() => _hint = const InvitationHint());
  }

  Future<void> _onChanged(bool checked) async {
    final version = disclosure?.version;
    setState(() => _checked = checked);
    await SpaceCodeRepo.setPendingInvitation(
      widget.pending.withAck(checked ? version : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return widget.fallback;
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final hint = _hint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8.0,
        children: [
          Row(
            spacing: 12.0,
            children: [
              const JoinCourseBadge(size: 32.0),
              Expanded(
                child: Text(
                  l10n.seatInviteTitle(
                    hint?.courseName ?? l10n.seatInviteYourCourse,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          ManagedConsentPanel(
            courseName: hint?.courseName,
            maskedEmailHint: hint?.maskedEmailHint,
            disclosure: disclosure,
            loadFailed: disclosureFailed,
            onRetry: loadDisclosure,
            checked: _checked,
            onChanged: _onChanged,
          ),
        ],
      ),
    );
  }
}
