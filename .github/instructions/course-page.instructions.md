---
applyTo: "lib/routes/chat/chat_details/space_details_content.dart,lib/routes/chat/chat_details/course_overview/**,lib/routes/courses/course_objectives/**"
description: "What a learner sees on a course's page: the Can-Do circles, the Can-Do card and its activity row, the full course plan, the Chats section, the section header, the course's credit and its image."
---

# Course Page

The course page is a course's main view. It opens on the **Can-Do circles** and the **Can-Do card**, then the sections **Chats**, [Participants](course-participants.instructions.md) and **More**. What its progress counts is [Can-Do progress](quests.instructions.md). This doc runs past 800 words because it covers the whole page, including the Can-Do circles and card that the Can-Do progress doc used to hold.

## The Can-Do circles

- One numbered circle per Can-Do that has activities, in course order. A gold ring shows its XP, a complete Can-Do shows its gold star, and the [next Can-Do](quests.instructions.md#the-next-can-do) is tinted. Its tooltip is its statement and its accessible name carries its state and XP, so colour is never the only carrier.
- A tap shows that Can-Do. A pointer marks the **Can-Do on show**: the one the learner picked, else the next Can-Do. The [course's map](world-map.instructions.md#the-can-do-on-show) and the [collapsed course bar](world-map.instructions.md#the-course-context-bar) show the same one. Opening an activity sets it to that activity's Can-Do, so closing the session returns there.
- **Class location:** a quiet grey bubble marks the circle the teacher's due dates put the class on: the first Can-Do still due, else the last dated one. A due date never blocks, hides or locks anything.
- **A bell** marks a circle not on show when a coursemate has pinged one of its sessions and it is still open, because the map shows only the Can-Do on show.
- While progress loads the circles shimmer, so nothing reads as zero. A course preview shows empty rings.
- No activity count sits beside the progress: it read as a second requirement.

## The Can-Do card

Top to bottom, for the Can-Do on show:

1. The Can-Do's number, the teacher's due date, and **Practice** with the Can-Do's word count, which opens [practice on its words](practice-exercises.instructions.md#objective-practice). The course's note sits below.
2. Its star and statement, linking to the Can-Do's detail page.
3. The Conversation and Practice legend and a bar of XP toward the star.
4. **Play**, the page's one solid button, pulsing while the Can-Do is unfinished. It opens the activity row's first card. Its label says whether it continues a session the learner is in, starts the next activity or replays a finished one.
5. The activity row.

- A course in another language shows [the switch](quests.instructions.md#progress-in-another-language) in place of progress.
- When every Can-Do is complete and no circle is picked, a course complete card replaces it, with the count of Can-Dos done and Practice.

## The activity row

The row holds every activity of the Can-Do, as [activity cards](activities.instructions.md#activity-cards), in this order:

1. a session the learner is in, whatever its mode, so a started activity is finished before a new one starts;
2. what they can play now: an unfinished activity they can start, or any with a live session;
3. what they have finished;
4. what they can't start yet, dimmed: more roles than the course can fill and no live session to join.

- Within each group the row uses the world map's [priority matrix](world-map.instructions.md#priority-matrix), so the page and the map agree. The map's first-map, dismissal and recency terms do not apply: the course's author picked its activities, nothing is dismissed here, and the row should not reorder while a learner reads it.
- A card whose session the learner is in reopens that chat; any other opens the activity's start page.

## The full course plan

- A "See full course plan" link under the card lists every Can-Do with its circle, statement and activities. It is a text link because educators asked to read the course's shape; it is not for choosing what to do next.
- Labels mark the next Can-Do as current and the class location. A complete Can-Do shows its star and muted text, and its activities stay playable. Each state is said in words, never by colour alone.

## The Chats section

- It shows the course chats the viewer has joined, then chats they can join, two at most, as [the Chats list's own rows](activities.instructions.md#activity-session-chat-list-rows). A student with nothing to show sees no Chats section.
- A course admin sees suggestions to create the Introductions and Announcements chats, and a **New course chat** button with a visible label: as an icon, teachers in a pilot did not find it and made no group chats. It is the only way to create a course chat, and students never see it.

## The section header

- Every section starts with its icon, title and actions. On a narrow screen the actions sit on their own line under the title; on a wide screen they follow the title and drop under it only when they don't fit.
- **See all** opens the section's full page, and shows only when that page holds more than the section. Its accessible name adds the section's title.
- A section may offer one other action, before See all: an icon named in its tooltip, or with a visible label when people miss the icon.

## Who made the course

- The page credits the quest's owner, not the room's admins ([who is credited](../../../.github/.github/instructions/quests.instructions.md#who-is-credited)).
- The name and avatar come from the owner's own profile, so a teacher controls their credit.
- The credit is prominent while someone chooses a plan to build a course on, because who made it is part of that choice. On an existing course it sits in More: the page opens on the teacher's description of their class, and a credit above it read as a banner over their words.

## The course's image

A course shows the image its admin set, else its quest's cover, else a letter, the same on every surface. A cover that fails to load is not retried until the app restarts, because retries added load to an already slow server.
