---
applyTo: "lib/routes/world/**"
description: "What the map shows when the learner is not inside a course: cities, course ships and open sessions, how they are chosen, and what tapping each one opens."
---

# World View

## Purpose

The world view is the map outside a course: where a learner finds courses to join and people to play with. Each course appears as a ship; activities are shown inside a course, on the [course view](course-view.instructions.md). What a city is, and how a course moves from city to city, are defined in the org [quests doc](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md#a-course-is-a-trip).

## The experience

1. Outside a course, the map shows cities and ships, each a small icon. Tapping one opens its card.
2. A ship stands for a course. It sits at the city the course has reached. The learner's own courses are marked as theirs.
3. A ship's card shows the course's name, who runs it, its members, its institution when it has one, and its description. It has one button: Open course, Join or Ask to join.
4. A city's card shows the city's name, how many activities are there, and a carousel of those activities. Its Explore button zooms the map into the city.
5. Zoomed into a city, the map shows the open sessions there and the activities the learner has already played there, each with a stamp.

## What the map shows

- No starter activities, because every learner is in a course ([courses](../../../.github/.github/instructions/course-spaces.instructions.md#where-a-learner-lands)).
- Only courses in the learner's target language, because the map is for the language they are learning. The sessions of a [language-exchange](../../../.github/.github/instructions/language-exchange.instructions.md) partner course will be the one exception.
- The search bar searches public courses by name, with the same match and order as the add-course list. It narrows the ships to the matching courses and lists them, and tapping one opens its card. The cities stay.
- One card is open at a time. It closes when the learner taps its X or opens another card.

## Ships

- Each course has one ship, an airship with no label. The course's name is on its card. Ships at the same city sit side by side, so each can be tapped.
- A ship sits at the city its course has reached ([progression](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md#progression)).
- Join on a ship's card opens the course's preview first. The preview offers Join for a Public course and Ask to join for an Approval required course.
- "Who runs it" lists the course's human admins and never the bot.
- The institution comes from the course's own institution record, which the teacher sets in the admin dashboard. It is a record of its own because the course plan and settings have other writers that rewrite them.

## Cities

- A city's icon has no label, because the base map already names the city. Its name is in its tooltip and is read by screen readers.
- The map zooms fully into a city only if one of the learner's courses has a Mission there. Only those cities' cards offer Explore.
- A city shows a lock when its Missions are not yet open to the learner in their course ([progression](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md#progression)).
- A city's icon grows as the learner earns XP in that city's activities, up to a limit, so that no city hides its neighbours.

## Stamps

- A stamp marks a city where the learner has earned any XP, and, zoomed into a city or inside a course, each activity they have played.
- On the dark base map a city is gold and its stamp is a light ring, because the primary colour does not show there. On the light base map the stamp is gold.

## Not built yet

**Intended — not yet implemented:**

- Open sessions on the world view: the ones in the learner's own courses, and later a language-exchange partner course's.
- One ranking that decides which cities, ships and sessions fit in the space available. Today every city on the shown courses' trips appears.
- A ship drawn travelling to its next city for about a day after its course moves, so the class sees that it moved. Activities stay playable meanwhile.
- A private course shown as a ship whose card says only "Private". This reveals that a class exists near that place.
- The admin dashboard setting that writes a course's institution.

## Open questions

- How cities, ships and sessions rank against one another.
- What the card of a course without dates shows of its route, when its members are at different cities.
- Whether a Protected course appears as a ship at all. It is not listed in course search, and a ship would show that it exists.
