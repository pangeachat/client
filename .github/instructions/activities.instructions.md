---
applyTo: "lib/features/activity_sessions/**,lib/features/quests/**,lib/routes/analytics/activities/**,lib/routes/chat/activity_sessions/**,lib/routes/chat/chat_details/**"
description: "How a learner finds and starts a conversation activity, its media, and the record it leaves."
---

# Activity System

## Purpose

How learners find and start activities, and the record they leave. What an activity is belongs to the org [activities doc](../../../.github/.github/instructions/activities.instructions.md); the start page's layout to [activity-start-page](activity-start-page.instructions.md); a running session to [activity-session](activity-session.instructions.md).

## The experience

1. A card on the map or in a course shows an activity's basics and first media item; opening it shows the whole activity.
2. The learner starts a new session or joins an open one. Joining, they pick a role and wait for the session to fill. Starting, they pick a role, then find players: ping the course, invite someone, or play with the bot.
3. Once it ends, it leaves Chats, and the Learning Objectives page keeps the record.

## Decisions

Who re-decides: unassigned throughout.

### A running activity is a chat room

- A session is a chat room, so it reuses the chat app.
- Activities belong to Missions, not courses, so a session needs no course.
- Cards and pins load the whole activity before opening. A screen over the read budget fills in over seconds, not blanking for a minute.
- A session is shared into every joined course listing its activity, so coursemates can join; a course shows only sessions it lists. A Content Studio course lists only activities under its own Can-Dos.
- The started-from course is where it was launched; a map launch records one only when exactly one joined course lists the activity.
- A session's panel waits at most 10 seconds for its room.

### Sessions in Chats

- A session's row shows the activity's photo in its live colour, with a course's avatar on it.
- A session leaves Chats once ended for everyone or saved. A replay's row shows the completed stamp, without XP. No "live now" strip: rows carry the state.
- A room a teacher joined only to review stays out of their lists until they take a role; links still open it, leaving the course leaves it, and the dashboard mutes it.

### The start page mirrors the room

- Each device can ping a course once a minute, against spam.
- Joining with one open role takes it. The page's back arrow leaves a session the learner only viewed.
- Ping, Invite and the online count use the started-from course, named there.

### Rating an activity

- Only the start page's info row shows an activity's rating, NEW until rated.

### Media is a carousel

- An activity's media is a list. The live session pages through it; the plan page, cards and pins show the first item. Today's generator gives each activity one.
- Tapping the plan page's lead image shows it whole.
- Nothing plays on its own; a video plays when tapped.
- Phones play video full screen; an inline player breaks the sheet. YouTube is embedded, never downloaded, per its terms.
- A video card wears a video tag; a play badge promised play in place.
- Captions follow the activity's language, for listening practice.
- On the web the embed takes the mouse only after a click, so scrolling works. Keys mirror YouTube's; focus never enters its frame.

### The Learning Objectives page

- One tile per Mission in the current language's joined courses, in course order; a shared Mission is one tile, and the open tile gets a border. No activity count, which was busy, and no Practice.
- Saved sessions outside the tiles close the list under Other activities, so a learner in no course keeps a record.
- A Mission's page names the course it was opened from, shimmers until its XP is in, and shows finished activities only; what comes next is the Mission card's job. Its vocab opens word cards in place.
- Practice is primary there, its main action, and secondary on the Mission card.
- A Mission only in another language shows its language and the switch.
- A session row's numbers come from its saved summary, so they match the end card; zero shows as zero, and without a summary only title and diamonds show.

## Open questions

- Which course does a shared session belong to, including whose avatar its Chats row shows? ([#9328](https://github.com/pangeachat/client/discussions/9328))
- Should browser or phone back leave a session the learner only viewed, as the back arrow does?
- Should a Mission's sessions from a second course or another language show on its tile, not under Other activities?
