---
applyTo: "lib/features/quests/**"
description: "Client-side progression gate — the one shared resolver for 'is this LO/activity locked?', its inputs (joined-course Mission sequences + per-Mission star rollup), fail-open behavior, and the surfaces that read it."
---

# Quests & Learning-Objective Progression (Client)

A **Quest** is the learner's ordered journey through **Learning Objectives** (learner-facing label: **Missions**). The cross-repo model — what a Mission is and the progression & **locking rule** (a Mission unlocks once the previous is satisfied at ≥ a star threshold; an **activity is locked iff every Mission it carries is gated and none is unlocked**; no gated Mission ⇒ never locked) — lives in the org doc [`quests-and-learning-objectives`](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md). This doc owns the **client-side resolver**: how the app computes that rule at render time from data it already holds, and which surfaces read it.

## One shared gate

"Is this LO (and its activities) locked?" is asked by many surfaces, so it is resolved **once** into a single shared gate, never re-derived per surface (re-deriving invites two surfaces drifting on the same question). The gate is built from two inputs the client already holds:

- **The ordered Mission sequences** of the learner's joined courses — each course's quest outline (ordered LO ids + the activities under each), cached and rebuilt on course join/leave.
- **The per-Mission star rollup** — a **star** is one orchestrator-awarded activity goal, read from awarded-goal state on the learner's own session rooms and summed per Mission across all its activities. No server-side progression endpoint is needed: every session that earned a star is a room the client can read. (Same collectible pattern as vocab/grammar — see [analytics-system.instructions.md](analytics-system.instructions.md).)

From those the gate resolves which Missions are unlocked vs gated, and answers `isLocked(activity)` by the activity-inheritance rule in the org doc.

**Fail open.** A surface that asks before the gate is built treats content as **unlocked** rather than blocking it, so a cold open (e.g. an activity link opened without visiting the map first) never strands the learner behind a gate we simply haven't computed yet. Locking is a guard, not a wall.

## Consumed by

Every surface that gates on progression reads the *same* shared gate, so the answer is consistent and computed once:

- the [world map](world-map.instructions.md) — locked pins render gray, unlocked purple, per-activity star progress as a fill (see its pin-display section);
- the **activity start page** — a locked activity's plan opens **read-only**: Start is disabled and shows the unlock reason, rather than launching a session behind the gate;
- the course/quest list and the powerups cluster, as they are built for v3.

The teacher-overridable threshold and the no-sequence-⇒-never-gated rule are part of the cross-repo rule (org doc); this doc only resolves them from local state.

## Future Work

File GitHub issues for these and link them here (use the `update-future-work` skill).

- A persisted per-Mission star total (server-side rollup) once reading every session room client-side becomes too costly at catalog scale.
