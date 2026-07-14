---
applyTo: "lib/features/quests/**"
description: "Client-side next-Mission resolver — the one shared answer to 'which Mission should this learner work on next, per quest?', its inputs (joined-course Mission sequences + per-Mission star rollup), and the ranking surfaces that read it."
---

# Quests & Learning-Objective Progression (Client)

A **Quest** is the learner's ordered journey through **Learning Objectives** (learner-facing label: **Missions**). The cross-repo model — what a Mission is, the star satisfaction threshold, and the rule that progression is **soft** (an ordered suggestion that only *ranks* content, never locks it) — lives in the org doc [`quests-and-learning-objectives`](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md). This doc owns the **client-side resolver**: how the app computes, from data it already holds, each quest's **next Mission** — the single ranking input the world map and other surfaces preference toward.

## One shared resolver

Nothing is locked, so the question is not "is this allowed?" but "where should the learner go next?" — and that is asked by many surfaces, so it is resolved **once** into a single shared answer, never re-derived per surface (re-deriving invites two surfaces drifting on the same question). It is built from two inputs the client already holds:

- **The ordered Mission sequences** of the learner's in-scope quests — their joined courses by default, or whatever the world map's quest filter selects — each quest's outline (ordered Mission ids + the activities under each), cached and rebuilt on course join/leave.
- **The per-Mission star rollup** — a **star** is one orchestrator-awarded activity goal, read from awarded-goal state on the learner's own session rooms and summed per Mission across all its activities. No server-side progression endpoint is needed: every session that earned a star is a room the client can read. (Same collectible pattern as vocab/grammar — see [analytics-system.instructions.md](analytics-system.instructions.md).)

From those, the resolver finds each quest's **anchor (next) Mission**: the **first Mission in quest order whose star total is below the satisfaction threshold**; once every Mission is satisfied, the anchor falls back to the **lowest-star Mission**, so a completed quest keeps pointing at the learner's weakest area instead of going silent. When several quests are in scope it yields an anchor **per quest** plus the global per-Mission star totals; consumers preference still-unsatisfied Missions and **accumulate** across quests (so an activity advancing several quests' unfinished Missions ranks higher) — the resolver just supplies the anchors and totals, the weighting lives in the consumer (see the [world map](world-map.instructions.md) Priority matrix).

**Fail soft.** A surface that asks before the resolver is built simply has no anchor yet and ranks on plain relevance — a cold open (e.g. an activity link opened without visiting the map first) is never blocked, because nothing is ever blocked. The resolver only sharpens ordering; its absence degrades to neutral ranking, not to a wall.

## Consumed by

Every surface that preferences by progression reads the *same* shared resolver, so the answer is consistent and computed once:

- the [world map](world-map.instructions.md) — the Priority matrix raises activities carrying the anchor Mission to the top of the relevance band, decaying for Missions further along; per-activity star progress renders as a fill (see its pin-display section);
- the **activity start page** — opens directly into play for every activity (nothing is gated), showing star progress and, where relevant, that this is a next-Mission activity;
- the **course panel's star display** (below);
- the course/quest list and the powerups cluster, as they are built for v3.

The teacher-overridable star threshold is part of the cross-repo rule (org doc); this doc only resolves it from local state.

## Star display on the course panel

The course panel tells the learner how far along they are, at two grains, computed from the same resolver inputs (joined-course outlines + per-activity stars from session rooms) so the numbers can never disagree with the map:

- **Per Mission**: earned stars over the satisfaction threshold (the teacher-overridable stars-to-unlock), with a progress bar. Stars past the threshold display raw (e.g. 12/7 — surplus effort shows); the bar clamps at full.
- **Per quest (the panel header)**: a total star count summing each Mission's stars **capped at its threshold** — one over-practiced Mission can't inflate quest progress — over a bar that fills toward the sum of the quest's thresholds.

A course **preview** (not joined) shows no star display — there is no learner progress to show. This builds toward the world_v2 tabbed course card (Figma "Everything outside of Chat"); until that card ships, the display lives on the existing course objectives panel.

# Panel > Chats
This panel

# Panel > Course Plan
This panel listing group of Activity Cards in multiple row.

## Various Activity Card UI
To help users easily scan and search for the right activity in Course listing, we design various Activity Card UI to help differentiate:

1. **Normal Activity Plan**
:🔘 Light Gray Card showing from top down: the large Activity image, the large Activity name, the row of star, and small Activity type next to number of role.

2. **Joinable/Open Activity**
:🟢 Green Card with an overlay tag [Open (number of open session/instance)] on the top right, and White text color. The tag will convey clearly that this Activity is Open and how many open sessions to choose. The tag also make it easy for screen reader, accessibility check. The color choice align with design of Green Joinable Map Pin V6. 

3. **Ongoing Activity**
:🟣 Purple Card with overlay tag [Ongoing]on the top right, and White text color. The tag will convey clearly that this Activity is Ongoing. The tag also make it easy for screen reader, accessibility check. The color choice align with design of Purple Ongoing Map Pin V6. 

4. **Need to invite more participant to start** 
:🔘 Light Gray Card with 30% Opacity, this convey that the Activity is still clickable but de-emphasized. If users want to know why, they can click on the card and see the "Uh oh, you need to invite NN people...".

[Figma link to design mockup](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13765-270419&t=pnytLg8wuPthDfDt-11)

# Panel > Participants

# Panel > More

## Future Work

File GitHub issues for these and link them here (use the `update-future-work` skill).

- A persisted per-Mission star total (server-side rollup) once reading every session room client-side becomes too costly at catalog scale.
- Teacher-set **hard** restrictions (an opt-in gate on top of the soft default), if classroom demand appears — deliberately not built today (see the org doc).
