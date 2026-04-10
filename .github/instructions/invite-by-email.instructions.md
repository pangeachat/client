---
applyTo: "lib/pangea/course_creation/**,lib/pangea/join_codes/**,lib/pangea/spaces/**"
---

# Invite by Email — Client

Cross-repo design: [conference-course-invite.instructions.md](../../../.github/.github/instructions/conference-course-invite.instructions.md)

> **Deferred to post-TESOL.** The TESOL flow is CMS-triggered. This doc covers the in-app teacher invite UI.

## Design

Teachers invite students by email from within the app. The client calls the Synapse `invite_by_email` endpoint directly using the teacher's own Matrix access token.

- **Request**: `{ room_id, emails, message? }` — teacher provides emails, room_id comes from the current space, message is optional.
- **Response**: `{ emailed, errors }`
- **Auth**: Teacher must be admin (power level 100) in the space.
- **UX**: Space settings → "Invite by Email" → text field for emails → submit → toast confirmation. Fire-and-forget from teacher's perspective.

## Future Work

- Bulk CSV upload for classroom rosters — no issue yet
- Show invite delivery status — no issue yet
