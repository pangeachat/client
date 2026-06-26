---
applyTo: "lib/routes/world/**,lib/features/quests/repo/**,lib/features/activity_sessions/**"
description: "World map design — the discovery surface: what content appears, the personalized default, search/filters, and the small/mid/large pin tiers that preference open sessions."
---

# World Map

The map is the canvas the whole app sits on; every other surface is a panel over it (the workspace model and the `?m=` map-scope token live in [routing.instructions.md](routing.instructions.md)). This doc covers what the map is *for* and what lives *on* it: the content, the personalized default, search, filters, and how items are displayed as pins. The base-tile and brand strategy is a separate concern — see [world-map-tiles.instructions.md](world-map-tiles.instructions.md).

## What the map is for

- **It is the place to discover essentially everything in Pangea Chat.** The job is to put the right thing in front of a learner at the right moment so they stay engaged and keep learning *socially*. Everything below serves that goal.
- **Preference open sessions.** Joining someone else's live activity session is more social and lower-friction than starting your own, so open, joinable sessions are always surfaced and always rank ahead of solo or not-yet-started content when the map decides what to feature. This recurs in ranking and display below because it is the map's strongest bias.
- **Never the whole library at once.** The map shows a curated, personalized, in-view subset, not a data dump; search and filters refine or widen from there. Legibility is a feature — a crowded map discovers nothing, which is why the display tiers below are an attention budget, not a rendering of everything available.

## What appears on the map

- **Today: located activities and their open sessions.** Geography lives on the activity (its coordinates), not on the course or quest — see the content model in [quests-and-learning-objectives](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md). The preferenced unit is an open **session**: a live, joinable instance of an activity.
- **Designed to generalize.** A map item is a located thing with facets, so new content types can join the same default → search → filter → display pipeline without a redesign: places and locations, opt-in users-as-content, and curated social items from the (future, supply-side) [world-feed](../../../.github/.github/instructions/world-feed.instructions.md).
- **A course scope narrows the candidate set.** Under the `?m=course:` map-scope token (see [routing.instructions.md](routing.instructions.md)) the map shows just that course's activities; the unscoped world view is the personalized default below. The content, ranking, and display pipeline is identical either way — the scope only changes which items compete.
- **The map changes focus only on a deliberate, focus-bearing selection.** A map focus is what the map is scoped or pointed at; it changes *only* when you select something that carries one — a **course** (scopes to its activities) or an **activity** (camera glides to its pin) — or via the **World/home** control, the one focus that names no item and so opens to the broadest possible, the whole world. Tapping a surface that carries no map focus (the Courses hub, Chats, Settings) overlays the map you left without changing it (#7087). The scope/focus token model lives in [routing.instructions.md](routing.instructions.md).

## The personalized default

Before any search or filter, the map shows **my L2, at or below my CEFR, in the current viewport, colored by state with my progress shown** — derived from signals the app already holds about the learner, with no new data capture. This is not a separate code path: it is just the [filters](#filters) pre-seeded (L2, CEFR, joined quests), the *initial* state and not a gate:

- Changing or clearing those filters and searching refine it; a one-tap **reset** returns to it.
- When the view is empty, offer a **widen** affordance (all languages, or zoom out) so personalization never dead-ends.

## Pin display: small, mid, large

Figma Designs: https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=12912-348899&t=ShPrG23Jo4zaTu2O-4

The map holds far more than it should ever show at full weight, so every item renders at one of three visual weights and only a few earn the heavy ones. The counts are an **attention budget** that scales with the visible map size; fewer is always better than crowding. The visual treatment is the [pin-tier frame](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=12912-348899).

| Tier | How many | What it is |
|---|---|---|
| **Small dot** | many (the long tail) | a plain dot — an available item, no detail until interacted with |
| **Mid pin** | ~5–10, by viewport size | a pin with an activity-type glyph; where strong matches and open sessions get featured |
| **Large card** | 1–3 only | the featured callout — simply the top of the score ([Priority matrix](#priority-matrix) below), no separate eligibility: a full preview card shown right on the map — image, title, type, level match, and a **row of stars** for the learner's progress. A live **joinable** session almost always wins it (joinable is the heaviest score term), and shows who is already in the session, its open slots, and a join affordance; when nothing is live, the learner's next-Mission frontier activity earns the slot instead. **Auto-featured** only where there is horizontal room (desktop / column mode); but the same card is the on-demand detail any pin expands to on tap (see [Interaction](#interaction) below), so a promoted card renders on a narrow screen too |

A pin's **state** is carried by color at every tier — the component is `Activity pin v3` in the frame above. There is no locked state: every activity is always playable, so progression only ever *ranks* content, never gates it (the [Priority matrix](#priority-matrix) and [quests.instructions.md](quests.instructions.md)). Two colors remain:

| State | Reads as | Meaning |
|---|---|---|
| **Available** | purple | playable — the default for every pin |
| **Joinable** | green | an open session is live and joinable right now |

**Progress is a fill, not a state.** A learner's progress in an activity is the stars earned toward its total (a star is one awarded activity goal — [activities.instructions.md](activities.instructions.md)). It renders by tier: on the **small and mid pins** as an **inner yellow dot whose radius grows with that fraction**, and on the **large card** as a **row of stars**. Empty means untouched, full means finished. Progress is orthogonal to the color state: it never recolors the pin and never hides it, so a finished activity stays on the map as a normal pin — the learner sees their trail without it crowding out the next thing to do. This replaces the earlier discrete "completed" state (a separate gold pin).

A **pinged** modifier (a hand glyph) marks an open session whose host has pinged the course to gather players (mechanics in [activities.instructions.md](activities.instructions.md)). Joinable wins the displayed color when both apply — a finished activity with a live session shows as joinable, green, to pull the learner back. Which items earn the scarce mid and large slots is the [Priority matrix](#priority-matrix) below.

**What ships.** Both colors plus the progress fill are derived from Matrix room state the client already holds. Progression itself is now purely a ranking input: the client resolves each quest's **next Mission** per [quests.instructions.md](quests.instructions.md) and the Priority matrix preferences activities in it — no pin is ever grayed out or blocked. A ping leaves no persistent room state, so **pinged** is detected best-effort by scanning recent course-space messages for the host's ping — a proxy whose efficacy we watch before investing in a persistent ping signal.

### Featured, selected, and focused

Beyond its color state and progress fill, a pin can carry one of three emphasis states. They are **decoupled** — different mechanisms, different lifetimes:

- **Featured** — *automatic*. The map enlarges the top-ranked pins to mid/large on its own, from the [Priority matrix](#priority-matrix) against the current zoom and filters. It is recomputed on every view: as the learner pans, zooms, or filters, *which* pins are featured re-ranks — the size budgets stay fixed, their occupants change. The learner does nothing to feature a pin.
- **Selected** — *manual, transient*. Tapping any pin **selects** it: it is drawn at the **large** card regardless of its featured standing, as a lightweight peek. A **selection clears on the next map move or zoom** (and on tapping the empty map, or selecting another pin). It never touches the score or what is featured — purely a momentary "show me this one big."
- **Focused** — *manual, persistent*. Tapping a **selected** card **focuses** the activity: its full detail panel opens and the camera settles on it. A focus **survives zoom and pan** — the deliberate "I'm working with this one" state, cleared only by closing the panel or focusing another activity. The focused pin carries a distinct **focused marker** at whatever size it currently sits.

The decoupling is the point: **featuring** is automatic and view-driven; **selection** and **focus** are deliberate user acts; and the **size budget** (how many large/mid a zoom allows) is kept separate from the **relevance score** (which pins rank into them). A pin can be focused without being featured, and featured without being selected.

### Interaction

**Tap to select, tap again to focus.** There is no separate preview popup. Tapping a small or mid pin **selects** it — it grows to its large card in place as a peek. Tapping a large card — whether auto-**featured** or **selected** — **focuses** the activity, opening its detail panel directly into play (nothing is gated). Tapping the empty map, or **any pan or zoom, clears the selection** and pins return to their featured sizes; a **focus** persists through all of that until the learner closes it or focuses another. (How this rides the workspace and folds on a narrow screen is in [routing.instructions.md](routing.instructions.md).) A **finished** activity (a full star row) keeps its color per the fill-not-state rule, adding a **Completed** marker and **Play again / Review**.

**Grouping** de-overlaps the map but is subordinate to the tiers: tier fill runs first, so any item that earns a **mid or large** slot renders at that weight even inside a dense area — it breaks out of the cluster rather than hiding in it. Only the leftover **small** dots that would overlap collapse into a count bubble — the `Grouped` variant, itself state-colored — which expands on zoom or tap. So a cluster only ever hides long-tail items; a high-ranked activity is always visible at its earned weight, never swallowed by the bubble it sits within.

## Priority matrix

Every item is ranked by **one weighted score** — there is no eligibility gate. Nothing is locked, and joinable is not a separate stage but the heaviest term, so the whole "what's allowed, then what ranks" split collapses into a single number that fills the tiers. Starting score:

`score = 3·joinable + relevance_band + 0.6·pinged + 0.3·recency − 0.5·finished`

- **joinable** `0/1` — an open, live session the learner can join right now. Weighted heaviest because joining someone's live session is the map's whole point (see [What the map is for](#what-the-map-is-for)); a live session normally takes the large card, but a strong next-Mission item still wins it when nothing is live, which is why joinable is a weight and not a gate.
- **relevance_band** `0–2` — the next-Mission gradient, below.
- **pinged** `0/1` — the open session's host is recruiting ([activities.instructions.md](activities.instructions.md)).
- **recency** `0–1` — newest first, a linear falloff over the last day (for a session, time since it opened).
- **finished** `0/1` — the learner has a full star row on *this activity*; it demotes so a done activity stays on the map (the trail) without taking a slot meant for the next thing to do. This is activity-level completion, distinct from Mission satisfaction in the band.

**Relevance is a next-Mission gradient that accumulates across quests.** For each quest in scope (the learner's joined courses by default, or whatever the quest filter selects), the client finds the quest's **anchor Mission** — the Mission the learner most needs next — and scores activities by how close their Missions sit to it. The anchor is the **first Mission in quest order whose star total is below the satisfaction threshold**; once every Mission is satisfied, the anchor becomes the **lowest-star Mission**, so a completed quest keeps pointing the learner at their weakest area instead of going flat. An activity's contribution *from one quest* rises to the top of the band when it carries that anchor and **decays smoothly** for Missions further along; a Mission that is **already satisfied contributes essentially nothing**, so the band never preferences work the learner has finished. When several quests are in scope, an activity's contributions **sum across them (saturating at the band ceiling)** rather than taking the single best — so an activity that advances *several* quests' still-unsatisfied Missions at once outranks one that advances only a single quest. That falls out of the same per-Mission weighting; there is no separate multi-quest branch, and the saturation keeps the band under the heavier `joinable` term. Outside any quest there is no anchor, so an activity scores on plain level/L2 fit — the same ranking, just without a frontier to pull toward. The anchors and star rollup are resolved by the shared client resolver in [quests.instructions.md](quests.instructions.md).

**The data the band needs** is nearly all already on the pin: its **level** (CEFR) and **L2** travel today, and activities already link their learning-objectives in the CMS. The choreographer's bbox card already carries those Mission refs (`learning_objective_refs` on each card from `/v2/activities/bbox`), so the only remaining gap is client-side: the client must parse them off the card and feed them into the band. The learner's in-scope quests and per-Mission star rollup come from the shared resolver, cached and refreshed on course join or leave rather than per re-rank. No new content model, endpoint, or CMS field is required.

**The bbox is the one always-on filter, and tiers are assigned over its survivors.** The current map viewport is a constant member of the [filter set](#filters) — never removable, continuously changing as the learner pans and zooms — and the tier budgets (large 1–3, mid ~5–10) are filled from the in-bbox candidate set against those **fixed counts**. So featuring is emergent from zoom with no change to any item's score: zoomed far out, many candidates compete for the same few slots and a low-score activity renders as a small dot (or, past the working-set cap, not at all — see [Scale boundary](#scale-boundary)); zoomed in, the field thins and that same activity naturally earns a mid or large slot. The bbox only decides membership; the single score then ranks the survivors.

**The pipeline.** Like a feed, the map retrieves a candidate set, scores it, then re-ranks for diversity:

1. **Candidates** — the filtered set inside the current bbox.
2. **Score** — the single formula above.
3. **Fill, with diversity** — fill large (1–3) then mid (~5–10) from the top of the score, avoiding a featured set that is all one course, Mission, or cluster. When more items tie for large than its budget (the common case: several joinable sessions live at once), the large slots **rotate through them, about every 5 seconds**, so each gets airtime; with three or fewer they stay static.

Re-ranking is debounced on pan and zoom (as the working-set re-fetch already is), and tier assignment is kept stable enough between nearby frames that a small pan does not reshuffle the cards. This runs client-side over the loaded set even while server-side viewport narrowing is deferred (see [Scale boundary](#scale-boundary)).

**Weights are levers, learned later.** The weights are hand-set starting points, tuned by observation: at our scale there isn't the engagement data to learn them from, and hand-set weights stay predictable and editable here — raising `joinable` or `pinged` pushes the map harder toward live, social practice; deepening the band's decay sharpens the pull toward the next Mission. A learned value-model — predicting join / complete / return — is the upgrade once the data exists. **Interests** become a term once captured (not tracked today).

## Search

Search matches content in the relevant view — title, description, and learning objective — results-as-you-type; selecting a result flies the camera to it and opens its preview. Searching what is already loaded in view is the starting scope; off-view / global search is a later option.

## Filters

Filters are the single mechanism that defines the candidate set; the [Priority matrix](#priority-matrix) then ranks within it. The set is:

- **Viewport (lat/long bbox)** — the one **constant** filter: always applied, never removable, driven by the map camera. Its role in tiering is in the Priority matrix above.
- **Selected quests**, **target language (L2)**, **CEFR level**, and **a set of Missions** — optional, all-via-a-dropdown. Selecting a quest also sets the next-Mission anchor that the band ranks toward.
- **Free text** — typed in the search bar ([Search](#search)).

The optional filters are seeded from the personalized default (my L2, my CEFR, my joined quests) and a one-tap **reset** restores them; each active one shows below the search bar as an **X-able pill**. This replaces the always-on toggles that previously sat under the bar. **Completion state, theme, and interests** come later, once the content model carries them and a captured-interests signal exists; interests are a deliberate captured preference, never proxied from free text.

Design intent: a change to *which* items exist widens or narrows the candidate set (a re-query); a change that only hides already-loaded items refines in place. Keep the cheap, indexed dimensions as set-changers and the rest as in-view refinements so the map stays responsive.

## Scale boundary

Map content is fetched through a **stable server contract** (the choreographer), not direct client-to-CMS queries, so the display and interaction design here is insulated from how the server narrows results. The catalog is currently small enough to return all placed items (clustered) and apply the CEFR band on the client; true viewport-narrowing and server-side CEFR banding are deferred until density warrants them. The returned working set is capped at a limit; when more items match than the cap, the map **signals that more exist** rather than over-fetching, and zooming or filtering narrows toward what fits. Track the density triggers in [scaling-watchlist](../../../.github/.github/instructions/scaling-watchlist.instructions.md).

## Future Work

File GitHub issues for these and link them here (use the `update-future-work` skill). Deferred design threads: client-side parsing of the bbox card's Mission refs (the choreographer already projects them) and a cached joined-course objective set, both needed for relevance banding; a backend endpoint for **map-wide open-session discovery**, since the client can only see open sessions in the learner's joined courses — surfacing strangers' joinable sessions across the map (the core preference-open-sessions goal) needs the choreographer to expose them; evaluating the **best-effort pinged detection** (recent course-space message scan) before adding a persistent ping signal; a generalized map-item pipeline for non-activity content; users-as-content (opt-in location); world-feed social items as a content source; server-side viewport narrowing and CEFR banding.
