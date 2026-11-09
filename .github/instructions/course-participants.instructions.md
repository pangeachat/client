---
applyTo: "lib/pangea/spaces/course_participants.dart,lib/pangea/spaces/load_participants_builder.dart,lib/routes/chat/chat_details/course_overview/course_participants_preview.dart,lib/routes/chat/chat_details/course_participants_page.dart,lib/routes/chat/chat_details/participant_card.dart"
description: "The course page's Participants section — who is listed and in what order, what a card shows and why it shows no progress, the preview and the full page, and how a member is reached from it."
---

# Course Participants

The course page's people section is a plain **Participants** list: who is in the course, so a learner can find a teacher or a classmate and start a conversation. It replaced a ranked Leaderboard ([client#9776](https://github.com/pangeachat/client/issues/9776)). Mission progress is personal now, and teachers see each student's progress on their own dashboard, so a student's progress does not need to be public to the class. A regular chat's participants page is a different surface.

## What a card shows

Each member is a card with their avatar, name and, when they have one, a role or membership badge. A card shows no stars, level or medal ring, and the list has no ranks.

## Who is listed, and in what order

- **Admins come first**, then the other joined members. Each group runs A to Z by display name, with the Matrix id settling equal names, so the order stays the same across loads and says nothing about who has done what.
- **Invited and knocking members come last**, on the full page only, invited before knocking, wearing their badge.
- **The bot is not listed.**

The list appears once the member list has loaded, so names do not reorder under the reader.

## The preview (the course page's section)

The section is headed **Participants** with the group icon. Below the header is one line of cards, cut to what fits the width. Its header actions are the invite shortcut, whenever the viewer may invite, and **See all**, only when the full page holds something the line does not: a member who did not fit, or any pending member.

## The full page (See all)

The dismissable hint banner, then every card in a centered wrap: admins, joined members, pending members. An invite tile closes the wrap when the viewer may invite.

## Reaching a member

Tapping a member's avatar opens the member actions menu (start a conversation, view the profile, and the admin actions). Every list is one Tab stop with the arrow keys inside it ([accessibility.instructions.md](accessibility.instructions.md), "One Tab stop per list"), and a card is one node, announced as its name and badge.
