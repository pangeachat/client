---
applyTo: "lib/routes/world/**,lib/features/quests/repo/**,lib/features/activity_sessions/**"
description: "What the world map shows: its pins and their ranking, focus, search, filters and the course context bar."
---

# World Map

## Purpose

The map is the canvas the whole app sits on; every other surface is a panel over it ([routing](routing.instructions.md)). It is where learners discover activities, above all open sessions to join, so they keep learning socially. Google Maps is the reference; base tiles are in [world-map-tiles](world-map-tiles.instructions.md).

## The experience

1. The map opens on the learner's target language, every filter at "All", narrowing nothing until they ask.
2. Each activity is a pin: a few large cards, some mid pins, the rest dots, coloured by state; played ones wear a gold stamp, leaving a trail.
3. Tapping a pin grows it to its card and opens its plan beside the map, or in a half-open phone sheet with the map live above.
4. Search and three pills (level, party size, status) narrow the pins; when nothing shows, a card names the one fix that works.
5. Selecting a course scopes the map to its activities.

## Decisions

### Pin display

- The visible map width caps how many pins and cards show, cards first to go, because a crowded map discovers nothing. — Unassigned
- Dots never cluster, a lighter pin never covers a heavier one, and a card without room becomes a lighter pin. — Unassigned
- The X demotes, never removes, and lapses after ten minutes, so nothing is ever hidden. — Unassigned
- Pins show XP earned, not goals, because goals pay XP every session. — Unassigned

### Pin state

- State shows by colour and shape, never colour alone, for accessibility. — Unassigned
- An available activity the course cannot yet staff dims but still opens. — Unassigned

### Priority matrix

- One score ranks every pin and hides none, though a played activity is never a card; live sessions weigh most, since joining is more social and easier than starting. — Unassigned
- Weights are hand-set levers tuned by watching, until there is data to learn them. — Unassigned
- A new learner's world map sinks activities needing three or more players, since the bot fills one seat; in a course they keep their place, because its author chose them. — Unassigned

### Discovering joinable sessions

- A session shows as open only with a free seat and someone in it, so a green pin never dead-ends. — Unassigned
- Inside a course only the sessions it lists count; strangers' sessions stay off the map for now. — Unassigned
- Panning re-checks live sessions, so the map feels current. — Will

### Focus

- Focus changes only on choosing a course, activity or World; Chats or Settings leave the map as it was. — Unassigned
- The camera never moves for a course, since no one place fits it; focusing an activity pans without zooming; only the focus button zooms. — Unassigned

### Filters

- Search and pills live only on the world map, so the search bar tells it from a course's map. — Unassigned
- Language comes from settings, not a pill: learners only want languages they study. — Unassigned
- An empty level shows the nearest level with content, lower on a tie, and says so; a silent widen would hide the gap. — Unassigned

### The course context bar

- A scoped map always names its course: learners started course activities thinking they were on the world map. — Unassigned
- A joined course's map shows only the Mission on show, to match the learner's current work; a ping elsewhere puts a bell on that Mission's circle. — Unassigned
- The bar is the card at rest, toggled by one control and never closed; only the learner collapses it. It shows only in an otherwise empty left column, though the map then names no course. — Unassigned

### Keyboard access

- One Tab stop with arrows inside, since ninety Tab stops would wall off everything else. — Unassigned

## Open questions

- Which ranks higher, the learner's own live session (this doc) or one to join (the code)?
- This doc rotated tied large cards every five seconds; the code never does. Still wanted?
- Does a dot's first tap open the plan (the code, [routing](routing.instructions.md)) or only grow its card?
- The code shows no L1 sessions, which this doc preferred, and skips the language filter in course scope. Intended?
- This doc had the map clear a course's ping badge; since #7842 only the course page does. Still wanted?
- This doc hid the bar's chevron from screen readers; the code announces it. Which?
- The code never signals pins hidden by the fetch cap, as this doc said. Wanted?
