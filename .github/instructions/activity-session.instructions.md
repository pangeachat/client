---
applyTo: "lib/routes/chat/activity_sessions/**,lib/routes/chat/choreographer/activity_orchestrator/**,lib/features/activity_sessions/**,lib/features/download/**"
description: "What a learner sees inside a running activity session and when it ends: the goal header, target vocab, the summary, saving, the bot's seat, the chat background, rating and the transcript."
---

# Activity Session

## Purpose

What a learner sees while playing a conversation activity and when it ends. Finding and starting one, and its media, belong to [activities](activities.instructions.md) and the [start page](activity-start-page.instructions.md).

## The experience

1. The chat opens with the activity's media on top and a goal header pinned above the messages: the learner's goals as diamonds, their session XP and the current goal.
2. Target vocab the learner uses turns gold, in messages and in the vocab chips.
3. Earning a goal fills its diamond; earning them all turns the header gold.
4. The learner taps "I'm done!" and their own summary appears at once, with a rating card. In a roleplay, the other players' summaries join it as each finishes.
5. The session saves itself and leaves Chats. Its transcript can be downloaded from the chat's menu.

## Target vocab in the conversation

- A set phrase is one vocab entry, matched word by word; a word matches any form.
- One rule drives the gold highlight and the used chips, so they agree. Analytics stays per word.

## The goal header

- The header stays pinned and looks like a button, because it opens the goal list. Only its top row opens and closes it.
- Session XP is a number, so the eye stays on the goal; it and earned diamonds' XP show only to a role-holder in their current language.
- A narrow window shrinks the header's padding, never the diamonds, because the header covers chat.
- Diamonds keep the goals' order; the active goal, highlighted, is the first unfinished. An earned diamond flies up to the active goal's slot.
- The header's left slot offers to switch to the session's language when the learner can switch to it.
- The open list describes every goal. "I'm done!" works early and finishes the learner's own role; "Wait, I'm not done!" undoes it. Admins get "End for all", except in two-person bot sessions.
- A long goal is cut with Show more; one that fits is plain text, so nothing falsely looks tappable.
- All diamonds earned turns the header gold, "I'm done!" replacing the goal.
- With no goals it reads "Activity actions", so nobody is stranded.
- On staging the team reports a wrong diamond from the open list, with a required comment and, for a missing one, the message that earned it.
- A report changes no diamond, and every failure shows, because a lost report is a lost complaint.

## The summary

- Each learner's summary is made when they finish, in either mode, with no group blurb ([activity summary](../../../.github/.github/instructions/activity-summary.instructions.md)).
- The summary replaces the header, showing the picked participant's goals, the viewer's own by default.
- A failed summary can be retried, and a learner can flag one to be regenerated. A failed regeneration keeps the old summary; a failed translation shows it as written.

## Completion saves itself

- A finished session saves even if it finished while the learner was away.

## The bot's seat

- When the bot took the last seat on its own, after the session sat open for an hour, the chat says so; after a day it adds that the bot is waiting for a message, since it sent none. A seat a learner asked the bot for shows no note.

## The chat background

- No activity image behind the chat, as it was too busy over the map, unless a per-device setting fades it in as the media scrolls away, replacing the wallpaper.

## The rating card

- It appears once the learner's role is finished, trusted as proof of play.
- A submitted rating is final until a new version; dismissing hides it for this visit.
- A rejected comment keeps the card open; an owner's own rating closes it quietly.

## Downloading the transcript

- Any member can download, since it shows only what they can read; web only until the native path is tested.
- The menu also has Search, Chat details and admin-only Delete. Invite leaves once the session ends for everyone; End activity shows while the learner holds an unfinished role in a started session, Leave until they take a role in one.

## Open questions

- The app still waits until every player is done and shows one shared summary with a group blurb. Per-learner summaries need the bot and choreographer changed first.
- Should research-study or minor-heavy rooms restrict exporting everyone's messages?
- Should an archived session show its timeline and saved summary?
