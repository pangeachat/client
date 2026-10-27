---
applyTo: "lib/features/quests/**,lib/features/course_plans/**,lib/routes/courses/course_objectives/**"
description: "How progress through a course's Missions is measured, which Mission is next, and how stars, goal diamonds, the course page and activity cards show it."
---

# Quests & Learning-Objective Progression (Client)

## Purpose

A quest is a course's ordered list of **Missions**, and progression only suggests, never locks ([org doc](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md)). This doc decides how the app measures progress through each Mission, names the next one, and shows both.

## The experience

1. A course page opens on numbered **Mission circles**, each ringed in gold by its XP: complete Missions are stars, the current one is tinted, and "Class location" marks where the teacher's due dates put the class.
2. Below, the **Mission card** for the Mission on show: its can-do statement, XP toward its star, Practice, and **Play** on its first activity.
3. A saved session banks its XP, goals included, into its Mission; practising the Mission's words anywhere fills it too.
4. At the course's threshold the star fills and the analytics bar's star count rises.
5. Once every Mission is complete, a course-complete card replaces the Mission card.

## Decisions

Re-decider for every line: unassigned.

### Stars and goal diamonds

- A star marks a Mission, outlined until complete; activities have none. Teachers asked for it: goal counts said little about what a student can do.
- A goal diamond is one activity goal, shown in a session's goal header and the start page's role cards; activity cards show XP, since goals pay every session and a best-session count undersold replays.
- The star count counts each Mission completed in a joined course in the current language once.

### What fills a Mission

- A Mission is complete when its XP reaches the course's threshold: its activities' XP plus practice on its words. XP has no ceiling, so any Mission with an activity can be completed.
- Only saved sessions count. Repeats add up: XP is effort, and the per-construct cap is the only farming guard.
- An activity's XP counts in every course listing it, wherever it was played: it is the learner's work, so card, Mission and start page agree.
- Practice outside a session counts toward every Mission listing the word, used before or not.
- Hiding or swapping a course's activity never lowers a Mission's XP: the hidden activity's XP and words still count.

### Language scope

- Progress shows only for content in the current language, since XP is kept per language; another language's course offers a switch, and the learner's base language a plain note without Practice.

### One shared resolver

- The next Mission is computed once and shared by every surface that ranks by progression, so no two drift.
- A finished quest has no next Mission, rather than point back at done work.
- Totals are per course: Missions recur across courses with different activities, so blending would credit one course's work to another and undo its pins.
- Until the answer exists, surfaces rank on plain relevance; nothing is ever blocked.
- The app stores each student's Mission numbers per course for the teacher dashboard to read, so the two never disagree ([client#9643](https://github.com/pangeachat/client/issues/9643)).

### Progress display on the course page

- A preview shows no progress, and no activity count sits beside it: it read as a second requirement.
- While a joined course's progress loads, its circles and Mission card shimmer rather than show a zero.
- The Mission on show rides the URL, so course page, collapsed bar and course map agree; a bell flags pings elsewhere, since the map shows only that Mission.
- A due date never blocks, hides or locks anything.
- The full plan is a quiet link, for the course's shape rather than what to do next; a complete Mission mutes but stays playable.

### The Mission card

- Play continues the learner's session before starting another, so started activities get finished.
- The activity row is the Mission's whole queue: the learner's sessions, playable, finished, then what the course can't fill. Each tier uses the map's ranking, so they can't drift, minus its big-group penalty (an author picked these) and time decay (it would reorder under a reader).

### Activity cards

- One card everywhere; a live state is a frame plus a named pill, never colour alone. A card the course can't fill dims but stays tappable.
- Finished means XP from a saved session in the current language. The stamp shows that XP, so every surface shows one number.

### Who made the course

- The credit comes from the owner's profile, so a teacher controls it.
- It is prominent while choosing a plan, then sits in More, not as a banner over the teacher's description.
