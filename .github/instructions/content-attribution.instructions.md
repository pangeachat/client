---
applyTo: "lib/routes/chat/activity_sessions/**,lib/routes/courses/**,lib/features/quests/**,lib/features/activity_sessions/**"
description: Who a piece of content is credited to on screen — the owner behind an activity or a course, where the name and avatar come from, and what shows when there is no person to credit.
---

# Content attribution

Activities and courses are made by people. A teacher builds a course for their class, tunes its activities by hand, and their learners should be able to see whose work they are doing. This doc owns **who gets credited on screen and how that credit is resolved**; it does not own who may *edit* content (that is ownership as write-protection, in the choreo's [content-sync](../../../2-step-choreographer/.github/instructions/content-sync.instructions.md) and the augment sweep) nor who may *see* it (visibility, in [activities.instructions.md](activities.instructions.md)).

## Who is credited

The credited person is the content's **owner**, the same field those other two systems use:

| Content | Owner field | Shape |
| --- | --- | --- |
| Activity | `res.plan.user_id` | the owner's MXID, stored on the row |
| Course (quest) | `quest-plans.owner` | a relationship to the owner's `matrix-users` row; the read path resolves it to an MXID before it reaches the client |

Matrix identity is **env-local**, so an owner MXID is only meaningful on the node that issued it. Content promoted between environments keeps the target's own owner where it has one — the choreo's content-sync doc owns that rule. Attribution simply renders whatever the local owner field says.

## How the name and avatar resolve

1. **The owner's Matrix profile.** Display name and avatar come from the profile, so a teacher controls their own credit by editing their Pangea profile — there is no second name for us to keep in sync.
2. **No usable profile → the stored MXID and a placeholder contact icon.** This covers a profile that does not resolve at all (an owner MXID with no account behind it, which real catalog rows have) and one carrying no display name.
3. **System-owned content → the PangeaChat name and logo.** `@system:pangea.chat` means nobody owns the row; it is Pangea's own catalog content, which is most of it, and crediting Pangea is accurate.

**INVARIANT: PangeaChat branding is reserved for system-owned content.** A person's work must never be credited to Pangea. That is the failure this design exists to prevent, and it is why an unresolvable owner falls back to a bare MXID — an ugly credit is recoverable, a wrong one is not. It reads as a prompt to the teacher to set a display name, which is exactly the right nudge.

## Where it appears

- **Activity start page** — the info row beneath the title, alongside the L2, level, participant count and rating. [activity-start-page.instructions.md](activity-start-page.instructions.md) owns that row's layout.
- **Course surfaces** — the course page header, wherever the course's identity is presented.

Attribution shows on **every** surface that shows the content, the public world map included. A teacher's identity travels with their material: that is the point of crediting it, and a credit that disappears in front of the audience most likely to want it would not be attribution at all. Anyone who does not want their name on public content should not be the owner of it.

## What this is not

- **Not a second identity system.** No attribution name or avatar is stored alongside the content; the Matrix profile is the single source. A row's credit changes when its owner edits their profile, with no content write.
- **Not an editorial byline.** It names the account that owns the row, not a person who has verified it. Quality evidence lives in audits.
