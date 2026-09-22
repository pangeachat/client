---
applyTo: "lib/pangea/spaces/course_leaderboard.dart,lib/pangea/spaces/load_participants_builder.dart,lib/routes/chat/chat_details/course_overview/course_leaderboard_preview.dart,lib/routes/chat/chat_details/course_leaderboard_page.dart,lib/routes/chat/chat_details/leaderboard_row.dart,lib/routes/chat/chat_details/participant_card.dart"
description: "The course page's Leaderboard section — who is ranked and how, what the preview and the full page show, the admin line and the pending members, and how a member is reached from it."
---

# Course Leaderboard

The course page's people section is a **Leaderboard** ([client#9212](https://github.com/pangeachat/client/issues/9212), replacing the plain Participants list). It shows who is in the course ranked by what they have done in the course's language, so activity is rewarded and coursemates have a friendly reason to keep playing. A regular chat's participants page is a different surface and is unchanged.

## Who is ranked, and how

- **Every joined member is ranked, admins included.** The bot is never ranked — it earns nothing — and does not appear on the leaderboard at all.
- **Invited and knocking users are not ranked.** They appear only on the full page, at the bottom, wearing their Invited or Knocking badge and no stats.
- **Order**: stars in the course's language, most first; level breaks a tie; then display name A to Z, then Matrix id. Equal members therefore keep one fixed order across loads instead of swapping places, and no rank is shown as a tie.
- The stars and level are the member's public-profile totals for the course's language — [quests.instructions.md](quests.instructions.md) ("Two star quantities") owns what those numbers mean. A course with no language recorded ranks each member on their own target language, the same fallback the old cards used.
- **Rows appear only once every member's profile has loaded.** Ranking on numbers that have not arrived would show an order and then reshuffle it under the reader; a spinner is honest, a wrong order is not.

[`CourseLeaderboard`](../../lib/pangea/spaces/course_leaderboard.dart) is the one ranking, shared by the preview and the full page so the two can never disagree.

## The preview (the course page's section)

The section is headed **Leaderboard** with the group icon. Its header actions are the invite shortcut, whenever the viewer may invite, and **See all**, only when the full page holds something the preview does not: more than three ranked members, any pending member, or an admin the line had to cut.

Below the header:

1. **The admin line** — every admin as a card wearing the Admin badge, with no stats (their stats are on their ranked row), smaller than a chat's member card so the podium stays the section's largest thing. One line, cut to the cards that fit the width, so a teacher is easy to find before the ranking starts.
2. **The podium** — the top three as full-width rows: a medal ring (gold, silver, bronze) around the avatar with the rank on a badge, a crown on first place, the name, then the star count and the level. Each row is tinted in its medal's colour.
3. **A lone member sees an Invite row in second place** when they may invite: a leaderboard of one says what the next step is. A viewer who cannot invite sees only the one row.

## The full page (See all)

The dismissable hint banner, then the admin line wrapped rather than cut, the same podium, then **fourth place onward as compact tiles** — rank number, avatar, name, stars and level — in two columns when the page is wide enough and one when it is not. Pending members follow as cards, and an Invite row closes the page when the viewer may invite.

## Reaching a member

**Tapping anywhere on a row or tile opens the member actions menu** (start a conversation, view the profile, and the admin actions), not only the avatar: on a full-width row a 56px hot spot would be a guessing game. Every list is one Tab stop with the arrow keys inside it ([accessibility.instructions.md](accessibility.instructions.md), "One Tab stop per list"), and a row is one node, announced as its rank, name, stars and level.
