---
applyTo: "lib/features/activity_sessions/**,lib/features/quests/**,lib/routes/analytics/activities/**,lib/routes/chat/activity_sessions/**,lib/routes/chat/chat_details/**"
description: "How a learner finds and starts a conversation activity, its media, and the record it leaves."
---

# Activity System

## Purpose

How learners find and start activities, and the record they leave. What an activity is belongs to the org [activities doc](../../../.github/.github/instructions/activities.instructions.md); the start page, with its waiting room, to [activity-start-page](activity-start-page.instructions.md); a running session to [activity-session](activity-session.instructions.md); Can-Dos, stars and XP to [Can-Do progress](quests.instructions.md).

## The experience

1. A card on the map or in a course shows an activity's basics and first media item; opening it shows the whole activity on its start page.
2. Cards are ranked to funnel users into finishing their sessions first, then joining open sessions, then starting a session as the last resort.
3. The learner starts a new session or joins an open one. Joining, they pick a role and wait for the session to fill. Starting, they pick a role, then find players: ping the course, invite someone, or play with the bot. A [discussion](#discussions) offers one Join instead, to a room the server picks.
4. After finishing, the learner is prompted to rate the activity and optionally comment, which affects its ranking for everyone.
5. Once it ends, it leaves Chats, and the Can-Dos page keeps the record.

## Activity cards

- Every list of activities draws the same card: the activity's first media item, its name, its mode (Roleplay or Discussion) and its role count.
- Cards and pins load the whole activity before opening. A screen over the read budget fills in over seconds, not blanking for a minute.
- A card shows its activity's state as the map does ([pin state](world-map.instructions.md#pin-state), [understaffed pins](world-map.instructions.md#understaffed-pins)): a frame, and a pill on its photo that names the state, so it is never colour alone. The pill reads "Open (N)" for N open sessions the course lists, "Ongoing", or "Waiting" with its players while seats fill.
- A finished activity wears a gold stamp with the learner's XP from it, beside any live state. Finished means XP from a saved session in the learner's current language, on every surface, so each shows the same number, the activity's XP [across every course](quests.instructions.md#what-fills-a-can-do). A course preview shows stamps too.

## A running activity is a chat room

- Activities belong to Can-Dos. A session belongs to one course ([activities](../../../.github/.github/instructions/activities.instructions.md)). Not built yet for roleplays: a roleplay session is still shared into every joined course that lists its activity, in the session's language. A course lists an activity by its own copy, else by its pins, not by Can-Do overlap, and shows only sessions it lists. The course it started from is always included.
- The started-from course is where it was launched; a map launch records one only when exactly one joined course lists the activity.

## Discussions

- The org doc owns what a [discussion](../../../.github/.github/instructions/activities.instructions.md#mode-discussion) is, who counts and how a room is picked. An older activity whose mode reads "Discussion" stays a roleplay.
- A learner with a seat in the course's room, done or not, goes straight to the chat; anyone else gets its [start page](activity-start-page.instructions.md#a-discussion). A seat in another course's room never opens or marks this course's discussion.
- Admins joined to watch can read and post. A student in a room without a seat gets Join in place of the composer.
- Its card shows "Joined" while the learner takes part, ranked as ongoing, and "Answered" once they have ended. It never takes the completed stamp; its XP shows once it is saved.
- In the chat, students' arrivals show, since they come over hours or days, but not admins' or the bot's; names carry no role. There are no suggestions.
- "I'm done" ends only the learner's own seat, and "Wait, I'm not done" undoes it, the saved record on the Can-Dos page included. It gives back the notification setting the learner had before ending, so a room they had muted stays muted. There is no "End for all" and no summary yet; the summary waits on the per-learner summary.

## Activity session chat list rows

- A session's row shows the activity's photo in its live color, with a course's avatar on it.
- A session leaves Chats once ended for everyone or saved. A replay's row shows the completed stamp, without XP. No "live now" strip: rows carry the state.
- A room a teacher joined only to review stays out of their lists until they take a role; links still open it, and leaving the course leaves it. New sessions already [include the course's admins](../../../synapse-pangea-chat/.github/instructions/course-session-admins.instructions.md), muted.

## Media is a carousel

- An activity's media is a list. The live session pages through it; the plan page, cards and pins show the first item.
- Tapping the plan page's lead image shows it whole.
- Nothing plays on its own; a video plays when tapped.
- Phones play video full screen; an inline player breaks the sheet. YouTube is embedded, never downloaded, per its terms.
- A video card wears a video tag; a play badge promised play in place.
- Captions follow the activity's language, for listening practice.
- On the web the embed takes the mouse only after a click, so scrolling works. Keys mirror YouTube's; focus never enters its frame.

## The Can-Dos page

- One tile per Can-Do in the current language's joined courses, in course order; a shared Can-Do is one tile, and the open tile gets a border. No activity count, which was busy, and no Practice.
- Saved sessions outside the tiles close the list under Other activities, so a learner in no course keeps a record. The session open in a chat is picked out there and scrolled into view.
- A Can-Do's page names the course it was opened from, shimmers until its XP is in, and shows finished activities only; what comes next is the Can-Do card's job. Its vocab opens word cards in place.
- Practice is primary there, its main action, and secondary on the Can-Do card.
- A Can-Do only in another language shows its language and the switch.
- A session row matches its end card: the same XP, and counts from its saved summary; zero shows as zero, and without a summary only title and diamonds show.

## Open questions

- Which course does a shared session belong to, including whose avatar its Chats row shows? ([#9328](https://github.com/pangeachat/client/discussions/9328))
- Should a Can-Do's sessions from a second course or another language show on its tile, not under Other activities?
