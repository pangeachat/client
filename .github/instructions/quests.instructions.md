---
applyTo: "lib/features/quests/**"
description: "Client quest model and the learning-objective progression gate — ordered LO sequence, satisfied = ≥10 stars (teacher-overridable), client-side star rollup, and where the gate is consumed."
---

# Quests & Learning-Objective Progression (Client)

A **Quest** is the learner's ordered journey through **Learning Objectives** (learner-facing label: **Missions**). The client reads a quest's ordered LO sequence from the CMS `quest-plans` collection; the cross-repo content model and the meaning of *satisfied* live in [`courses-and-activities-v3`](../../../.github/.github/instructions/courses-and-activities-v3.instructions.md) and choreo [`learning-objectives`](../../../2-step-choreographer/.github/instructions/learning-objectives.instructions.md). This doc owns only the **client-side progression gate** — how the app decides an LO is locked or unlocked — which the [world map](world-map.instructions.md) consumes to colour pins.

## The progression gate

The sequence is a single straight line, advanced one LO at a time. An LO is **unlocked** when it is the first in the sequence, or when the **previous LO is satisfied**; otherwise it is **locked**.

- **Satisfied = the learner has earned at least 10 stars in the LO** — the cross-repo threshold defined in choreo [`learning-objectives`](../../../2-step-choreographer/.github/instructions/learning-objectives.instructions.md). A **star** is one orchestrator-awarded activity goal (the same award the activity session shows; mechanics in [activities.instructions.md](activities.instructions.md)).
- **An LO's star total is summed across all of the LO's activities** for the learner, not per single activity — a learner can satisfy one LO across several different conversations, which is the bucket-grain intent of a Mission.
- **Teacher-overridable per course.** A teacher in teacher mode may raise or lower the threshold from 10; the override travels in course-space room state, exactly as the v1 topic gate's `activitiesToUnlockTopic` did. This is the same unlock mechanism as the retired Topics model, with stars replacing the old completed-activity count.
- **No sequence ⇒ never gated.** An activity reached outside a quest sequence (a standalone or purely global map pin with no course progression behind it) is always unlocked; locking only applies within a quest's ordered LOs.

## Computed client-side, no new endpoint

The gate is resolved on the client from Matrix room state the app already holds — awarded-goal state on the learner's activity-session rooms, rolled up per LO. Stars are the learner's own awards, so every session that earned one is a room the client can read; no server-side progression endpoint is required. The star tracker shares the vocab/grammar collectible pattern (see [analytics-system.instructions.md](analytics-system.instructions.md)).

## Consumed by

The [world map](world-map.instructions.md) is the gate's display surface today: locked LOs render their pins gray, unlocked pins purple, and per-activity star progress shows as a fill (see that doc's pin-display section). Other quest surfaces (the course/quest view, the activity start page) read the same gate as they are rebuilt for v3.

## Future Work

File GitHub issues for these and link them here (use the `update-future-work` skill).

- Cross-quest LO sequencing — a course space may hold more than one quest and LOs are shared across quests; resolving "the previous LO" when an LO sits in several sequences at different positions is deferred until multi-quest courses ship.
- A persisted per-LO star total (server-side rollup) once reading every session room client-side becomes too costly at catalog scale.
