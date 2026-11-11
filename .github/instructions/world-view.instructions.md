---
applyTo: "lib/routes/world/**"
description: "Planned, not built. What the map shows when the learner is not inside a course: cities, course ships and open sessions, how they are chosen, and what tapping each one opens."
---

# World View

**Intended — not yet implemented.** Today the map outside a course shows activity pins, picks a starter activity and searches activities ([world map](world-map.instructions.md)). Nothing below exists yet.

## Purpose

The world view is what the map shows when the learner is not inside a course. It is where a learner finds courses to join and people to play with. Each course appears as a ship. Activities are shown inside a course, on the [course view](course-view.instructions.md). What a city is, and how a course moves from city to city, are defined in the org [quests doc](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md#a-course-is-a-trip).

## The experience

1. Outside a course, the map shows three kinds of item: cities, ships and some open sessions. Each is a small icon. Tapping one opens its card.
2. A ship stands for a course. It sits at the city the course has reached. The learner's own courses are marked as theirs.
3. A ship's card shows the course's name, who runs it, its members and its description. It has one button: Open course, Join or Ask to join.
4. A city's card shows the city's name, how many activities are there, and a carousel of those activities. Its Explore button zooms the map into the city.
5. Zoomed into a city, the map shows the open sessions there and the activities the learner has already played there, each with a stamp.

## What the map shows

- The map shows only cities, ships and open sessions. Activities are shown inside courses, because the world view is for finding courses and people.
- No starter activities are shown outside courses, because every learner is in a course ([courses](../../../.github/.github/instructions/course-spaces.instructions.md#where-a-learner-lands)).
- The map cannot show everything, so one ranking decides which cities, ships and sessions appear in the space available. Activity pins are chosen the same way today.
- The open sessions shown are the ones in the learner's own courses. Once [language exchange](../../../.github/.github/instructions/language-exchange.instructions.md) exists, the sessions of a partner course are shown too.
- Only courses in the learner's target language appear, because the map is for the language they are learning. The sessions of a language-exchange partner course are the one exception.
- The search bar searches public courses.
- One card is open at a time. It closes when the learner taps its X or opens another card.

## Ships

- Each course has one ship, drawn as an airship with no label. The course's name is on its card.
- A ship sits at the city its course has reached ([progression](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md#progression)). When the course moves to the next city, the ship is drawn travelling there for about a day, so the class can see that it moved. Activities stay playable while the ship travels.
- A private course also appears as a ship. Tapping it shows only the word "Private". This does reveal that a class exists near that place.
- Join on a ship's card opens the course's preview first. The preview offers Join for a Public course and Ask to join for an Approval required course.
- "Who runs it" on a ship's card lists the course's human admins and never the bot.

## Cities

- A city appears only when the ranking picks it.
- A city's icon has no label, because the base map already names the city. Its name is in its tooltip and is read by screen readers.
- The map zooms fully into a city only if one of the learner's courses has a Mission there. Only those cities' cards offer Explore.
- A city shows a lock when its Missions are not yet open to the learner in their course ([progression](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md#progression)).
- A city's icon grows as the learner earns XP in that city's activities, up to a limit, so that no city hides its neighbours.

## Stamps

- A stamp marks a city where the learner has earned any XP. Zoomed into a city, or inside a course, a stamp marks each activity the learner has played. The learner can see where they have been at every zoom level.
- On the dark base map a city is gold and its stamp is a light ring, because the primary colour does not show there. On the light base map the stamp is gold.

## Open questions

- How cities, ships and sessions rank against one another.
- What the card of a course without dates shows of its route, when its members are at different cities.
- Where a course's institution comes from. Its card should show one, and no course record holds one yet.
- Whether a Protected course appears as a ship at all. It is not listed in course search, and a ship would show that it exists.
