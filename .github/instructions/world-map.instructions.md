---
applyTo: "lib/routes/world/**,lib/features/quests/repo/**,lib/features/activity_sessions/**"
description: "World map design — the discovery surface: what content appears, the personalized default, search/filters, and the small/mid/large pin tiers that preference open sessions."
---

# World Map

The map is the canvas the whole app sits on; every other surface is a panel over it ([routing](routing.instructions.md)). It is where a learner discovers what to do next and, above all, whom to do it with. Its base tiles are in [world-map-tiles](world-map-tiles.instructions.md), and Google Maps is the reference for how it should feel. This doc runs past 800 words because it owns the map's content, pins, ranking, search, filters and course bar. [Design frames](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13673-111364).

## The experience

1. The map opens on activities in the learner's target language around the camera, with no search or filter set.
2. Each activity is a pin in the colour of its state. The most relevant few show as cards, more as mid pins and the rest as dots.
3. Open sessions the learner can join rank first, because joining someone is more social and easier than starting alone.
4. One tap on a pin opens the activity.
5. Search and three filters narrow the map. An empty map says why and offers the way out.
6. Choosing a course scopes the map to that course.
7. Finished activities leave a trail of gold stamps around the world.

## What appears on the map

- Located activities and their open sessions. Location belongs to the activity, not to its course or quest ([quests](../../../.github/.github/instructions/quests.instructions.md)).
- Never the whole library: a crowded map discovers nothing, so the map draws a ranked subset sized to the screen.
- A course's map shows only that course's activities, and a course preview scopes the map the same way before joining ([course-preview](course-preview.instructions.md)). The scope changes which activities compete; ranking and display stay the same.
- A [discussion](../../../.github/.github/instructions/activities.instructions.md#mode-discussion) shows on the map of a course whose Can-Dos list it, never on the world map. Its pin's state and the room a tap opens come from the learner's seat in that course's room; without a seat the tap opens its start page. It never reads as an open session to join.

### The Can-Do on show

A joined course's map shows only the Can-Do on show: the one the learner picked in the [Can-Do circles](course-page.instructions.md#the-can-do-circles), else the course's next Can-Do. Nothing from another Can-Do appears, not a coursemate's open session and not the learner's own unfinished one. A picked Can-Do the course no longer has falls back to the next one, so the map and the circles agree.

This trades some joinable sessions out of view for a map that matches what the learner is working on. A coursemate's ping in another Can-Do puts a bell on its circle, and the learner's own sessions stay in Chats and on that Can-Do's card. A preview and the world map are not narrowed this way.

### Open sessions

- A session shows as open to join while it has not started, has a free seat, and someone is in it. The presence test keeps abandoned rooms off the map. The start page uses the same test, so a green pin never leads to a page with no Join.
- A learner sees open sessions in the courses they have joined and sessions they were invited to. Sessions in other courses are out of reach ([Future work](#future-work)).
- Inside a course, only the sessions that course lists count, so a session of the same activity started in another of the learner's courses does not show. The listing is the whole test: a member who leaves the course leaves their session listed. A session the learner was invited to, or opened by link, is never scoped out.
- Open sessions refresh within seconds of a change or a camera move. A session that fills leaves coursemates' maps and course pages without notifying anyone.

## The camera

- The camera moves for an activity, never for a course. Selecting an activity pans its pin into the map the panels leave uncovered, at the current zoom. A course's activities can be scattered, so no single place is right to point at; the pins alone show the new scope. A course preview is the exception and fits the course's activities ([course-preview](course-preview.instructions.md)).
- The focus button on an activity's page and on the course header is the one control that zooms: in on the activity, or to fit the course.
- Opening Chats, Settings or the Courses hub leaves the map as it was. World returns it to the whole world.
- Every screen can zoom out to nearly the whole world. The limit comes from the screen's size, because a fixed limit that suits a desktop strands a phone zoomed in.
- Drag pans; pinch, wheel and the +/- buttons zoom. Pinch and wheel apply at once around the pointer, because easing a direct gesture reads as lag. The buttons glide.

## Pins

### Small, mid and large pins

The visible map's width, the screen minus open panels, sets how many pins draw and how many of each weight. As it narrows the heavy weights empty first: no cards, then no mid pins, then only dots. A course collapsed to its [bar](#the-course-context-bar) does not count as an open panel. The counts are tuned in [one file](../../lib/routes/world/world_map_pin_budget.dart).

- **Dot:** a small plain dot. Dots draw one by one and may overlap; the map never groups pins into a count bubble.
- **Mid pin:** the state's icon, with the seat count while a session fills. An available activity shows its mode's icon. No label.
- **Large card:** the activity's own [card](activities.instructions.md#activity-cards) on a tail pointing at its place, with its state as a frame and a pill, a title in the learner's display language, and an X.
- Any activity can be a card except a finished one with nothing live. Live sessions score highest and take the cards first; the rest go to the best available activities, so a new learner never sees a map of bare dots.
- Cards never overlap, run off the screen or sit under a panel, and mid pins never stack or hide under a card. One that does not fit drops to a lighter pin. Lighter pins draw under heavier ones.
- Pins hold still while the camera moves and update when it settles.

### Pin state

A pin has one state, the first that applies. Colour and icon carry it together, never colour alone; the colours are [design tokens](design-tokens.instructions.md).

| State | Look | Meaning |
| --- | --- | --- |
| Ongoing | purple; an hourglass and seat count while waiting, a chat icon once started | the learner holds a role in a session they have not finished |
| Joinable | green; an open door and seat count | someone else's [open session](#open-sessions) |
| Played | the gold [played stamp](#played-stamps) | the learner finished it and nothing is live |
| Available | light purple; the mode's icon | playable, nothing live, not yet finished |

- Available is the quietest colour in both themes. On the dark map it is a deep muted purple, because the pale one made the least urgent state the loudest mark.
- A bell marks an open session whose host [pinged the course](activities.instructions.md). The map finds pings by reading recent course messages, a best effort to judge before building a lasting signal. It clears the course's unread badge once the ping shows, because the pin is where the learner sees it.

### Understaffed pins

The bot fills one role, so an activity needs one person fewer than its roles. An available activity the course cannot yet fill draws at half opacity, as a dot, mid pin or card, and still opens as normal. Only available pins dim: a live session proves people are present.

### Played stamps

- Finished means XP from a saved session in the learner's current language, the rule every [completed stamp](activities.instructions.md#activity-cards) follows. It does not mean every goal earned: the trail records what the learner did.
- With nothing live, the stamp is the activity's pin, reduced at dot size to a gold ring round a check. It never becomes a card.
- With a live session, the pin shows the live state. Its card wears the stamp and the learner's XP; its mid pin and dot carry no played mark.
- Pins and cards show XP, never a goal count ([Can-Do progress](quests.instructions.md#stars-and-goal-diamonds)). A discussion never takes the stamp.

### Tapping a pin

- One tap opens the activity's page, beside the map on a wide screen and as a low sheet on a phone with the pin visible above it. There is no hover or preview step.
- The pin becomes its card in place where the width allows, darkened slightly with a glow in its colour, so the learner can tell which activity is open.
- The focus survives pans and zooms. Closing the page, tapping another pin or the card's X ends it; tapping empty map does not.
- On a phone the map stays live around the sheet, so the learner moves from pin to pin without closing anything.

### Closing a card

A card's X demotes it to a lighter pin and never removes it. For ten minutes the activity ranks lower and cannot be a card, even when tapped; then it competes again, so an X never buries an activity for good. On the open activity's card, the X also closes its page.

## Priority matrix

One score ranks every activity. Score never hides or locks anything; it decides who gets the cards and mid pins, and which pins draw when more are loaded than the screen holds.

| Term | Weight | When |
| --- | --- | --- |
| Joinable | +3 | an open session the learner can join |
| Ongoing | +2.4 started, +1.6 waiting | a session the learner is in |
| Next Can-Do | 0 to +2 | highest for an activity on a joined course's [next Can-Do](quests.instructions.md#the-next-can-do), fading for later ones, nothing for completed ones; adds up across courses to the cap |
| Ratings | −2 to +2 | the share of thumbs up; unrated activities take the top, so new content is not penalised |
| Pinged | +0.6 | the host is gathering players |
| Recency | 0 to +0.3 | newest first, fading over a day |
| Completed | −0.5 | every goal earned, so finished work stays on the map without taking the next thing's place |
| Dismissed | −0.5 | its card was [closed](#closing-a-card) in the last ten minutes |
| First map | −2 | a learner who has finished nothing, on the world map, for an activity with three or more roles and no live session |

- At most one of joinable and ongoing applies. The gap between them sets how far the map favours joining others over resuming.
- The first-map term exists because a new learner alone cannot start an activity the bot cannot fill. It never applies in a course, whose author chose its activities.
- Ratings only reorder. They show on the activity's page, not on pins.
- Pins fill by score from the heaviest weight down. The cards are never all from one course or Can-Do, and when more activities tie for a card than there are cards, the cards rotate every few seconds.
- A few places are held for finished activities, so the trail is not crowded out.
- A tapped pin takes a card from the lowest-scored one.
- The weights are hand-set and tuned by watching the map; there is not yet the data to learn them.
- The same score orders the [course page's activity row](course-page.instructions.md#the-activity-row).

## Search

- Text matches an activity's title, description and Can-Do as the learner types, in their display language, and narrows the pins. On a wide screen it also lists the top-ranked results, and choosing one flies there and opens it. On a phone the pins are the results.
- Search covers everything loaded, not only what is in view, so a result can be off screen ([Scale boundary](#scale-boundary)).
- Search and filters belong to the world map. A course or a preview has neither, because the search bar is part of what tells the world map from a scoped one ([#8736](https://github.com/pangeachat/client/issues/8736)). Filters set on the world map still apply there, so the empty-map card stays on a wide screen as the way out.
- While an activity is open on a wide screen the search hides: a playtester took the filters for the activity's settings. It also hides when panels leave too little map for a usable bar.
- Touching the map closes the phone keyboard.

An empty map shows one card with one diagnosis and its remedy:

| What is wrong | Remedy |
| --- | --- |
| Matches exist outside the view | Zoom out to the whole world |
| The filters exclude every match | Clear the filters |
| The search matches nothing loaded | none |
| Nothing here and no search | Zoom out |

Zoom out greys at the zoom limit; it does not disappear. On a phone, where the whole world does not fit, it goes to the view that shows the most matching activities.

## Filters

- Two filters are always on: the view, and the target language from the learner's settings. There is no language filter, because a learner only wants content in the language they study.
- Three filters sit under the search bar, each one choice at a time and each starting at All: **Level** (one CEFR level), **Party size** (2 to 5, the activity's exact role count; 2 is the solo choice, with the bot) and **Status** (available, ongoing, open to join, waiting, completed).
- The map narrows nothing until asked, preferring breadth, and company over solo play. Changing level in settings does not set the Level filter.
- A reset appears once any filter is set and clears them all. Changing target language clears the search and the filters.

### Empty levels fall back to the nearest one with content

- Every level stays offered. Choosing one with no content shows the nearest level that has some, the lower on a tie, because easier content is the safer stand-in.
- A notice names the level shown; the filter keeps reading the level chosen. A silent switch would hide the gap, and dropping empty levels would strand a learner whose own level is one of them ([#8401](https://github.com/pangeachat/client/issues/8401)).
- The notice gives way to the empty-map card.
- The real fix is content. The learner's level is reported to [analytics](google-analytics.instructions.md), so each level's audience can be sized before content is commissioned.

## The course context bar

On a wide screen a collapsed course panel is a bar: the course's name, its share and focus buttons, its Can-Do circles and a chevron. It exists so a scoped map always says which course scopes it; without it a learner started a course activity believing they were on the world map ([#8736](https://github.com/pangeachat/client/issues/8736)).

- It cannot be closed. Only World ends the course scope ([routing](routing.instructions.md#the-course-context)).
- Tapping the bar opens the card, and tapping the card's header collapses it. The card grows out of the bar and shrinks back, and the header does not move.
- Only the learner collapses the card; screen width never does.
- The bar draws only when nothing else is open on the left. With another panel open the scoped map names no course, an accepted cost: the rail and the card name it.
- A phone has no bar. The course panel rests at its peek there and shows the same header.

## Keyboard access

Pins are drawn on a canvas, so their keyboard and screen-reader access is authored ([accessibility](accessibility.instructions.md)).

- The map's pins are [one Tab stop](accessibility.instructions.md#one-tab-stop-per-list). Arrow keys move through the drawn pins in ranked order: cards, mid pins, then dots.
- Enter or Space is a tap. Esc steps back to the group.
- The focused pin wears the two-tone [focus ring](accessibility.instructions.md#focus-rings).
- A pin's name says what it shows: the activity, its language and level, a live session's seats, its state, a ping, and a finished activity's XP.
- The wide search results take arrow keys and Enter.

## Scale boundary

- The map loads through one server read, which ranks the learner's target language by quality score and fills its cap of 200 from the camera outward: the activities in view, then a margin around it, then the best of the rest of the language. Nothing is hidden by score, so a low-scored activity still loads when the learner moves to it or when few better ones are near (Will, 2026-11-19). The answer travels compressed so the map stays fast.
- Filling the cap with the best of the rest is what keeps off-view search and the zoom-out remedy working. An off-view activity outside the loaded set reads as no match until the camera nears it; a text search on the server would close that gap.
- The Level filter is applied in the app after the cap, so in a large language at a wide zoom an activity at the chosen level can sit past it. The app sending the chosen level as a ranking preference is the next step ([scaling-watchlist](../../../.github/.github/instructions/scaling-watchlist.instructions.md)).
- When more activities match than the cap returns, the map says that more exist.
- Past the screen's pin count, activities are not drawn. They are never clustered.

## Future work

- Open sessions in courses the learner has not joined.
- A signal that a session is still active, so an abandoned one stops scoring as joinable.
- A lasting ping signal, if the best-effort one proves its worth.
- Other content on the map: places, people who opt in, and [world feed](../../../.github/.github/instructions/world-feed.instructions.md) items.
- Filters for theme and interests, and multiple target languages.
- The chosen level sent to the server as a ranking preference.
- A played activity's words fanning out from its stamp, built and switched off until its design is revisited.
