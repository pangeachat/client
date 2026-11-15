---
applyTo: "lib/features/quests/**,lib/features/course_plans/**"
description: "What a learner sees of their progress through a course's Can-Dos: stars and goal diamonds, what earns XP toward a Can-Do, progress in another language, the next Can-Do, and which activities a Can-Do shows."
---

# Can-Do Progress

How a learner's progress through a course's Can-Dos is counted and shown. Org docs own what a [quest](../../../.github/.github/instructions/quests.instructions.md) and a [Can-Do](../../../.github/.github/instructions/can-do-statements.instructions.md) are and how a class [moves through a course](../../../.github/.github/instructions/course-spaces.instructions.md#progression). The circles and Can-Do card are in [course page](course-page.instructions.md), activity cards in [activities](activities.instructions.md#activity-cards).

## The experience

1. Each Can-Do in a course has a star, outlined until the learner completes it.
2. Playing its activities and practising its words earn XP. At the course's threshold the star turns gold and stays gold.
3. The app points the learner to their next Can-Do.

## Stars and goal diamonds

- A **star** marks a Can-Do. The course page's circles show a number until the Can-Do is complete. No activity has a star.
- The analytics bar counts the Can-Dos completed in the learner's joined courses in their current language. A Can-Do two courses share is one star, and a previewed course never counts. The count shimmers until known, because a zero would read as no progress.
- A **goal diamond** marks one activity goal, worth 50 XP: outlined while open, gold once earned.
- Diamonds show in the session's goal header and the start page's role cards. Activity cards and chat rows count no goals; a card shows the activity's XP instead, because a best-session diamond count undersold a replayed activity.
- Teachers asked for stars to mean Can-Dos: a goal count said little about what a student can do.

## What fills a Can-Do

- Each activity the course lists for it adds the XP of the learner's saved sessions: [message XP](analytics-system.instructions.md), 50 XP per goal, and practice done in the session. Repeat sessions add up; the per-word XP cap is the only limit on replaying.
- A session counts once it is saved, which finishing does.
- A saved session counts in whichever course it was played, or none, so an activity's card, its Can-Do's meter and its start page show one number.
- Totals are per course: two courses can give one Can-Do different activities, and each sums only its own.
- Practice outside a session counts toward every Can-Do whose activities' suggested vocab holds the word, even a word the learner never used in a session.
- Every surface splits a Can-Do's XP into Conversation (messages, calls and goals) and Practice, in two golds with a legend. Its detail page also splits it by skill and says how much came from goals. Hearing a message read aloud earns no XP.
- The instructor sets the threshold on the [dashboard](../../../.github/.github/instructions/admin-dash.instructions.md#teacher-surfaces-in-the-client); the default is 1,000 XP. XP has no ceiling, so any Can-Do with an activity can be completed.
- A completed Can-Do stays complete when the threshold is raised, and its meter counts against the threshold it was completed at. One completed before thresholds were recorded can show its star over a meter that is not full.
- The app does not send the dashboard a lower XP while a saved session is still loading, so a teacher never sees a Can-Do drop and come back.

## Progress in another language

- XP is kept per target language, so progress shows only for content in the language the learner is learning now. A session counts when it was saved under that language. A course with no language recorded counts.
- A course in another language shows "Switch to {language}" in place of its progress. Its details and Practice first offer [the switch](profile.instructions.md#switching-from-context), then carry on.
- A course in the learner's base language cannot be switched to: it says so and shows no Practice.

## The next Can-Do

- A course's next Can-Do is its first incomplete one in course order. A course with every Can-Do complete has none, because naming one sent a finished learner back to completed work.
- Every surface reads the same answer, so they cannot disagree: the [world map](world-map.instructions.md#priority-matrix)'s ranking, the course page, the star count and the [Can-Dos page](activities.instructions.md#the-can-dos-page).
- Today nothing is locked and the order only ranks. Locking is being brought back:

**Intended — not yet implemented:** cities open by due date or by completing a Can-Do ([course progression](../../../.github/.github/instructions/course-spaces.instructions.md#progression)).

<a id="per-course-activity-pinning"></a>

## Which activities a Can-Do shows

- A course with its own Can-Do list shows that list's activities ([content lifecycle](../../../.github/.github/instructions/content-lifecycle.instructions.md#course-spaces)). A course never shows the quest in place of its own list. Not built yet ([pangeachat/client#9828](https://github.com/pangeachat/client/issues/9828)): a course with no list of its own, or one that cannot be read, still shows for each Can-Do the course's pins, else the plan's [selected activities](../../../.github/.github/instructions/quests.instructions.md#each-entry-in-the-can-do-sequence), else every activity. A course preview shows the plan's selection.
- Pins or a selection naming none of the Can-Do's activities are ignored, so a Can-Do can always be completed.
- A Can-Do's note is the course list's, or the plan's while the course has no list.
- The course's map shows the same activities. The world map is never filtered by a course's choices.

## Future Work

- Count a session's XP as it is earned, not when the session saves ([client#9698](https://github.com/pangeachat/client/issues/9698)).
