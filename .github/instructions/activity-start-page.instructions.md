---
applyTo: "lib/routes/chat/activity_sessions/**,lib/routes/world/**,lib/widgets/layouts/mobile_nav_widget.dart,lib/widgets/layouts/workspace_shell.dart"
description: "Each state of the activity start page, and how its sheet sizes, moves and owns its container."
---

# Activity Start Page

## Purpose

What a learner sees on tapping an activity, in every state. Its job is to start a conversation in as few choices as possible. What it shows follows the session room.

## The experience

1. A sheet opens over the map (a card on the web).
2. The learner chooses how to play, picks a role, and waits for the seats.
3. Afterwards, Completed lists their sessions.

## The sheet and its container

- On a phone it rests minimized, the top rows and buttons only, grown to fit them; drag up or tap for full, down to close. It always reopens minimized.
- It owns its rounded container, hiding the nav icons until it closes and, at full, the analytics bar, with no added scrim, shadow, border or accent. Even at full it stays inset: a map panel, not a full-screen chat.

## The top of the page

- Title row: a control top-left (a close X, or a back arrow to the open sessions list or the course card), then the title, share and focus; flag sits with the description, off the buttons. Info row, always: creator, language (its chip [switches to it](profile.instructions.md#switching-from-context)), level, players, and the rating, shown nowhere else.
- The creator is the owner, from their profile, so teachers control their credit, else their account id and a placeholder icon. Pangea's name and logo only for Pangea's own: an ugly credit beats giving Pangea a teacher's work.
- A vocab word opens its card; another word switches cards in one tap; any other tap only closes it.

## The CTA row

- **In a session**: once full, opening goes straight to the chat; until then Continue, to its waiting room, and nothing to start or join.
- **Two players**: equal tiles, Play with Pangea Bot (always the learner's own session) and Play with others, on the right for a right thumb.
- **Three or more**: Join open session when one waits, else Start.
- A loading bar shows until sessions are known, so the choice never changes meaning.
- The first choice is filled, later ones quieter; labels wrap rather than scroll. Completed sits below for a viewer with sessions to review.
- A course with too few members for the activity shows a notice of how many more it needs, Invite for those who can invite, and Pick a different activity unless minimized. A session with no course needs none.

### Open sessions

- Listed above the buttons at full, with each open role and when members were last online, most recent first. Played roles go unmarked: activities are replayable.
- Play with others joins one, a course ping's else the most recently active (the list's top), rather than opening its own, so partners meet. If the seat is gone it tries the next, up to three, so simultaneous tappers pair up; then it starts a new session.
- One open role is taken straight away; several keep the role picker. Backing out of a viewed session leaves it, so looking joins nobody.
- A quiet Start my own keeps joining the default.

### Completed sessions

- Opens with the learner's total XP from the activity across courses, as their card's stamp ([what fills a Mission](quests.instructions.md#what-fills-a-mission)). Lists this course's sessions, then their others under Other courses, to match the total; an admin sees everyone's, own first. Each shows the XP it paid the viewer.

## The waiting room

- A status line: time waited since creation, and coursemates online; or, when the bot will take the last seat ([when](../../../.github/.github/instructions/open-activity-sessions.instructions.md)), a countdown to it.
- Invite friends and Ping course participants lead, both filled; Play with Pangea Bot follows, quieter. Each device can ping once a minute, against spam.
- Ping, Invite and the online count use the course the session started from, named on the page.
- A "…" menu takes share's place, so inviting isn't mistaken for sharing, with the chat-list row's actions ([routing](routing.instructions.md#a-chats-header-actions)).

## When the activity can't be fetched

- A gone activity whose plan the room kept shows view-only, with a "no longer supported" notice. With none, only that notice, the participants, roles and Leave.
- A failed load shows an error, no retry; the page waits for the activity, the chat does not.

## Open questions

- Should the minimized sheet grow with very large text? Code clips it.
- Should browser or phone back leave a viewed session, as the back arrow does?
