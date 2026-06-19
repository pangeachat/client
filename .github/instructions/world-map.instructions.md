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

- **Today: located activities and their open sessions.** Geography lives on the activity (its coordinates), not on the course or quest — see the content model in [courses-and-activities-v3](../../../.github/.github/instructions/courses-and-activities-v3.instructions.md). The preferenced unit is an open **session**: a live, joinable instance of an activity.
- **Designed to generalize.** A map item is a located thing with facets, so new content types can join the same default → search → filter → display pipeline without a redesign: places and locations, opt-in users-as-content, and curated social items from the (future, supply-side) [world-feed](../../../.github/.github/instructions/world-feed.instructions.md).
- **A course scope narrows the candidate set.** Under the `?m=course:` map-scope token (see [routing.instructions.md](routing.instructions.md)) the map shows just that course's activities; the unscoped world view is the personalized default below. The content, ranking, and display pipeline is identical either way — the scope only changes which items compete.

## The personalized default

Before any search or filter, the map shows **my L2, at or below my CEFR, in the current viewport, colored by my progress** — derived from signals the app already holds about the learner, with no new data capture. This default is the *initial* state, not a gate:

- Filters and search refine it; a one-tap **reset** returns to it.
- When the view is empty, offer a **widen** affordance (all languages, or zoom out) so personalization never dead-ends.

## Pin display: small, mid, large

The map holds far more than it should ever show at full weight, so every item renders at one of three visual weights and only a few earn the heavy ones. The counts are an **attention budget** that scales with the visible map size; fewer is always better than crowding. The visual treatment is the [pin-tier frame](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=12912-348899).

| Tier | How many | What it is |
|---|---|---|
| **Small dot** | many (the long tail) | a plain dot — an available item, no detail until interacted with |
| **Mid pin** | ~5–10, by viewport size | a pin with an activity-type glyph; where strong matches and open sessions get promoted |
| **Large card** | 1–3 only | the featured callout, **reserved for open joinable sessions** (see below): a full preview card shown right on the map — image, title, type, level match, who is already in the session and its open slots, join affordance. Renders on the map only where there is horizontal room (desktop / column mode); on a narrow screen these same top-ranked joinable sessions render as mid pins and open the preview sheet on tap |

A pin's **state** is carried by color (and, for two states, a glyph) at every tier — the component is `Activity pin v3` in the frame above:

| State | Reads as | Meaning |
|---|---|---|
| **Locked** | gray | not yet available, behind progression |
| **Unlocked** | purple | available, not started |
| **Completed** | gold, with a star | the learner has finished it |
| **Joinable** | green | an open session is live and joinable right now |

A **pinged** modifier (a hand glyph) marks an open session whose host has pinged the course to gather players (mechanics in [activities.instructions.md](activities.instructions.md)). When several states apply to one item, the highest on the priority ladder wins the displayed color — a completed activity with a live session shows as joinable, green, to pull the learner back. Which items earn the scarce mid and large slots is the [Priority matrix](#priority-matrix) below.

**What ships first.** Unlocked, completed, and joinable are all derivable from Matrix room state, so they ship together; **locked** needs progression rules that aren't on the client yet, so until that lands a not-yet-started activity simply shows as unlocked. A ping leaves no persistent room state, so **pinged** is detected best-effort by scanning recent course-space messages for the host's ping — a proxy whose efficacy we watch before investing in a persistent ping signal.

The preview card that the large tier shows proactively is the *same* card that opens on demand when a learner taps a smaller pin (a bottom sheet on mobile — see [routing.instructions.md](routing.instructions.md)). **Grouping** is separate from the tiers: where pins would overlap they collapse into a count bubble — the `Grouped` variant, itself state-colored — that de-overlaps the map and expands on zoom or tap.

## Priority matrix

What an item is, and how prominent it becomes, is decided by several factors rather than one, so we don't collapse them into a single grid. They split the way modern feeds split ranking: hard **eligibility** rules first, a tunable **score** second, a **diversity** pass last.

**State — the dominant axis, a gate (not a score).** An item can match several states at once; the highest on the ladder `locked < unlocked < completed < joinable` is the one displayed, and it caps the item's prominence:

- **Joinable** dominates and is the only state eligible for the **large** card — joining a live session is the goal (see [What the map is for](#what-the-map-is-for)).
- **Completed** always renders **smallest**: shown so the map stays lived-in, never re-pushed.
- **Locked** is shown dimmed for a full world and legible progression, never promoted.

State is a gate rather than a weighted term because these are hard rules: no relevance score should lift a locked or completed item into the spotlight.

**Relevance — the ranking axis, a weighted score.** Among the items a tier's state gate allows, relevance decides which win the scarce slots. Starting score:

`score = relevance_band + 0.6·pinged + 0.3·recency`

- **relevance_band** — the dominant term: joined-course objective `3` > level-appropriate L2 objective `2` > in my L2 `1` > global `0`.
- **pinged** `0/1` — the open session's host is recruiting ([activities.instructions.md](activities.instructions.md)).
- **recency** `0–1` — newest first, decaying with age (for a session, time since it opened).

The boosts sum to at most `0.9`, under one band step, so they only **reorder within a band** — a joined-course item always outranks a level-appropriate one. That preserves the strict priority above while giving one comparable number to fill slots with and to feed a future model. The remaining `0.1` of headroom is held for a **social-proof / urgency** term (a nearly-full session) once that signal exists.

**The data the bands need** is nearly all already on the pin: its **level** (CEFR) and **L2** travel today, and activities already link their learning-objectives in the CMS — the only gap is that the world-map pin's working-set card *drops* those objective refs in transport, so it must carry them (the choreographer bbox card projects them; the client parses them). The learner's **joined-course objective set** is resolved on the client from the courses they belong to and cached, refreshed on course join or leave rather than per re-rank. No new content model, endpoint, or CMS field is required.

**The pipeline, borrowed from feed ranking.** Instagram- and TikTok-style feeds retrieve a candidate set, score it, then re-rank for diversity; the map mirrors that:

1. **Candidates** — the personalized, in-view, filtered set.
2. **Score** — the formula above, under the state gate's size ceiling.
3. **Fill, with diversity** — fill large (1–3, joinable-only) then mid (~5–10) from the top of the score, avoiding a featured set that is all one course, objective, or cluster. When more joinable items qualify for large than its budget (the common case: several joined-course sessions live at once), the large slots **rotate through them, about every 5 seconds**, so each gets airtime; with three or fewer they stay static.

**The pipeline is recomputed for the active viewport.** The candidate set is what's in the current bbox and the budgets are per-view, so panning or zooming re-ranks and re-fills the tiers: the featured cards are always the best things where the learner is *currently looking*, and the bar to be featured rises as a wider view brings more candidates into competition. Re-ranking is debounced on pan and zoom (as the working-set re-fetch already is), and tier assignment is kept stable enough between nearby frames that a small pan does not reshuffle the cards. This runs client-side over the loaded set even while server-side viewport narrowing is deferred (see [Scale boundary](#scale-boundary)).

**Weights are levers, learned later.** The weights are hand-set starting points, tuned by observation: at our scale there isn't the engagement data to learn them from, and hand-set weights stay predictable and editable here — raising `pinged` pushes the map harder toward live, social practice. A learned value-model — predicting join / complete / return — is the upgrade once the data exists. **Interests** become a term once captured (not tracked today).

## Search

Search matches content in the relevant view — title, description, and learning objective — results-as-you-type; selecting a result flies the camera to it and opens its preview. Searching what is already loaded in view is the starting scope; off-view / global search is a later option.

## Filters

Filters refine or widen the working set from the personalized default:

- **Target language (L2)** and **CEFR** — the spine of the default, changeable to explore beyond it.
- **Completion state** — new / in-progress / done, so a learner can find fresh content or resume.
- **Theme / Mission completion, and interests** — later, once the content model carries them and a captured-interests signal exists. Interests are a deliberate captured preference, never proxied from free text.

Design intent: a change to *which* items exist widens or narrows the working set (a re-query); a change that only hides already-loaded items refines in place. Keep the cheap, indexed dimensions as set-changers and the rest as in-view refinements so the map stays responsive.

## Scale boundary

Map content is fetched through a **stable server contract** (the choreographer), not direct client-to-CMS queries, so the display and interaction design here is insulated from how the server narrows results. The catalog is currently small enough to return all placed items (clustered) and apply the CEFR band on the client; true viewport-narrowing and server-side CEFR banding are deferred until density warrants them. The returned working set is capped at a limit; when more items match than the cap, the map **signals that more exist** rather than over-fetching, and zooming or filtering narrows toward what fits. Track the density triggers in [scaling-watchlist](../../../.github/.github/instructions/scaling-watchlist.instructions.md).

## Open questions

- The **recency** decay shape and half-life.

## Future Work

File GitHub issues for these and link them here (use the `update-future-work` skill). Deferred design threads: carrying learning-objective refs on the world-map pin (the bbox card projects them, the client parses them) and a cached joined-course objective set, both needed for relevance banding; the **locked** pin state, once client-hydrated progression rules exist; evaluating the **best-effort pinged detection** (recent course-space message scan) before adding a persistent ping signal; a generalized map-item pipeline for non-activity content; users-as-content (opt-in location); world-feed social items as a content source; server-side viewport narrowing and CEFR banding.
