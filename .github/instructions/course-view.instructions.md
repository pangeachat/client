---
applyTo: "lib/routes/world/**"
description: "What the map shows inside a course: the course's cities along its route, its ship, the activities at a city, how the camera moves, and the preview before joining."
---

# Course View

## Purpose

The course view is what the map shows when the learner is inside a course. It shows that course's trip: its cities in order, the route between them, the course's ship, and the activities at the city the learner is working in. The same view is used to preview a course before joining. The map outside a course is the [world view](world-view.instructions.md). Which cities are open to a learner is defined in the org [quests doc](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md#progression).

## The experience

1. When the learner chooses a course, the map changes to that course's view and fades to the city where the ship is.
2. The activities of the Mission the learner is looking at appear at that Mission's city. When the learner picks another Mission, the map fades to that Mission's city.
3. Zoomed into a city, the map shows its activities. The ones the learner has played have a gold stamp.
4. When the learner taps an activity in a city that is not open yet, the app says when it opens.
5. When someone previews a course before joining, the map fades to show the whole route. Nothing on the map can be opened in a preview.

## What the map shows

- Only this course's cities and activities are shown, so everything the learner plays belongs to the course they chose.
- In a course the learner has joined, only the activities of the Mission they are looking at are shown. The rest of the route is shown as cities.

## How the camera moves

- When the app moves the map to another city or to a whole route, it fades to the new view. It does not pan or zoom there, because a pan or zoom loads map tiles for every place it passes and is jarring to watch. The learner's own panning and zooming are unchanged.
- Choosing a course fades to the city where its ship is.
- Leaving a course fades back out to the whole world, the same view the reset button gives.
- Picking a Mission fades to that Mission's city, because its activities are there.
- A preview fades to the whole route, because the person previewing wants to see the course.

## Entering a city early

- A learner can enter a city before it opens, by paying a cost. This applies whether the course opens cities by date or by each student's progress, so no learner is locked out of a city. The org quests doc owns this rule and has not yet decided what the cost is ([progression](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md#progression)).

## The preview

- In a preview nothing on the map can be opened, because opening an activity would take the person away from deciding whether to join.
- Choosing a trip before a course exists happens on the planner's map in the educator dashboard ([teacher onboarding](../../../.github/.github/instructions/teacher-onboarding.instructions.md)). It is not this view.

## Not built yet

**Intended — not yet implemented:**

- The course's cities joined by a route, with its ship and which cities are open. The route shows every city, open or not, so the learner sees the whole trip ahead.
- Entering a city early, for a cost. The offer is built behind a setting that is off, because the cost is not decided.
