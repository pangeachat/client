---
applyTo: "lib/features/quests/**,lib/features/course_plans/**,lib/routes/courses/course_objectives/**"
description: "Client-side next-Mission resolver — the one shared answer to 'which Mission should this learner work on next, per quest?', its inputs (joined-course Mission sequences + per-Mission star rollup), and the ranking surfaces that read it."
---

# Quests & Learning-Objective Progression (Client)

A **Quest** is the learner's ordered journey through **Learning Objectives** (learner-facing label: **Missions**). The cross-repo model — what a Mission is, the star satisfaction threshold, and the rule that progression is **soft** (an ordered suggestion that only *ranks* content, never locks it) — lives in the org doc [`quests-and-learning-objectives`](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md). This doc owns the **client-side resolver**: how the app computes, from data it already holds, each quest's **next Mission** — the single ranking input the world map and other surfaces preference toward.

## One shared resolver

Nothing is locked, so the question is not "is this allowed?" but "where should the learner go next?" — and that is asked by many surfaces, so it is resolved **once** into a single shared answer, never re-derived per surface (re-deriving invites two surfaces drifting on the same question). It is built from two inputs the client already holds:

- **The ordered Mission sequences** of the learner's in-scope quests — their joined courses by default, or whatever the world map's quest filter selects — each quest's outline (ordered Mission ids + the activities under each), cached and rebuilt on course join/leave.
- **The per-Mission star rollup** — a **star** is one orchestrator-awarded activity goal, read from awarded-goal state on the learner's own session rooms. Per activity, the learner's stars are their **best single session** (the most goals awarded to them in any one session of it — repeat sessions do not accumulate); the Mission total sums those per-activity bests across the Mission's distinct activities. Both rules are the org doc's satisfaction model. No server-side progression endpoint is needed: every session that earned a star is a room the client can read. (Same collectible pattern as vocab/grammar — see [analytics-system.instructions.md](analytics-system.instructions.md).)

From those, the resolver finds each quest's **anchor (next) Mission**: the **first Mission in quest order whose star total is below the satisfaction threshold**; once every Mission is satisfied, the anchor falls back to the **lowest-star Mission**, so a completed quest keeps pointing at the learner's weakest area instead of going silent. When several quests are in scope it yields, **per quest**, an anchor and that quest's own per-Mission star totals; consumers preference still-unsatisfied Missions and **accumulate** across quests (so an activity advancing several quests' unfinished Missions ranks higher) — the resolver just supplies the anchors and totals, the weighting lives in the consumer (see the [world map](world-map.instructions.md) Priority matrix).

**Progression star totals are per course, never blended across them** ([client#7771](https://github.com/pangeachat/client/issues/7771)) — the separate per-person total on a participant card is a different quantity, not an exception to this (below). Missions are a shared catalog reused across quests, so two joined courses routinely carry the same Mission with *different* activities. A star total only means something against the activity set it was summed over: rolling several courses together would clamp one course's effective threshold against another course's content and credit its stars, and would silently undo that course's activity pins. Accumulation across quests is the *consumer's* job (the map's band), not a property of the totals. Where two courses genuinely list the **same** activity, each counts it once on its own — that needs no merging, since both outlines carry it.

**Fail soft.** A surface that asks before the resolver is built simply has no anchor yet and ranks on plain relevance — a cold open (e.g. an activity link opened without visiting the map first) is never blocked, because nothing is ever blocked. The resolver only sharpens ordering; its absence degrades to neutral ranking, not to a wall.

## Consumed by

Every surface that preferences by progression reads the *same* shared resolver, so the answer is consistent and computed once:

- the [world map](world-map.instructions.md) — the Priority matrix raises activities carrying the anchor Mission to the top of the relevance band, decaying for Missions further along; per-activity star progress renders as a fill (see its pin-display section);
- the **activity start page** — opens directly into play for every activity (nothing is gated), showing star progress and, where relevant, that this is a next-Mission activity;
- the **course page's Suggested Activities row** — the same Priority matrix, scored over the course's own activities (below);
- the **course panel's star display** (below);
- the course/quest list and the powerups cluster, as they are built for v3.

The teacher-overridable star threshold is part of the cross-repo rule (org doc); this doc only resolves it from local state.

## Star display on the course panel

The course panel tells the learner how far along they are, at two grains, read from the same shared resolver the map uses — one answer, never re-derived per surface — **scoped to the course being viewed** (above). A course it can't resolve (a preview, or before the resolution lands) shows no star display rather than another course's numbers.

Every displayed threshold is the **effective threshold**: the configured stars-to-unlock (teacher-overridable, default 10) clamped to the sum of earnable stars across the Mission's activities — the org doc's invariant that a Mission is always satisfiable from its content ([client#7663](https://github.com/pangeachat/client/issues/7663)). Earnable per activity is its goals-per-role count, falling back to the min across roles for plans predating the uniform-count generation invariant (org [`activities`](../../../.github/.github/instructions/activities.instructions.md) doc). The resolver computes the clamp; displays never re-derive it.

- **Per Mission**: earned stars over the effective threshold, with a progress bar. Stars past the threshold display raw (e.g. 12/7 — surplus effort shows); the bar clamps at full.
- **Per quest (the panel header)**: a total star count summing each Mission's stars **capped at its effective threshold** — one over-practiced Mission can't inflate quest progress — over a bar that fills toward the sum of the quest's effective thresholds. The clamp is what keeps this denominator honest: it can never exceed the stars the course's activities actually offer.

A course **preview** (not joined) shows no star display — there is no learner progress to show. This builds toward the world_v2 tabbed course card (Figma "Everything outside of Chat"); until that card ships, the display lives on the existing course objectives panel.

## Two star quantities, and how a reader tells them apart

Stars are displayed in two different senses, and both appear on the course page.

- **Course progress** — the panel displays above: how far this learner is through *this course*, capped per Mission, scoped to the course's own activities. It answers "how much of this course is done".
- **A member's star total** — on the participant cards in the course page's Participants section: how many stars that person has banked in the course's language across everything they have played, uncapped and not course-scoped. It answers "how much has this person done". It is read from their public profile, since a viewer cannot see the session rooms another member earned stars in ([profile.instructions.md](profile.instructions.md)); the course page is where classmates become visible to each other, which is why it is shown there.

The participant card is roughly one avatar wide and has no room for a label, so the two are distinguished by **form**: course progress always displays as a fraction over a bar, a member's total always as a bare count with no denominator. The full sense — how many stars, in which language — is carried in the card's accessible name and its hover tooltip, which cost no space. A denominator added to the participant card would collapse the distinction and should not be — that is the confusion this rule exists to prevent.

The participant card shows the member's total for **the course's language** beside their level, which is already a per-language number, so both values on the card share one scope.

## Suggested Activities on the course page

The course page opens on a shortlist: one row of activity cards headed **Suggested Activities**, answering "what should I do in this course right now?" ([client#8741](https://github.com/pangeachat/client/issues/8741)). It names no Mission. The Mission-by-Mission plan — every Mission with its can-do statement, star count and activities — sits one tap away behind "See full course plan" in the section's header, and is where a learner reads the course's shape.

The row is ranked by the **same [Priority matrix](world-map.instructions.md#priority-matrix) the world map ranks pins by**, scored over the course's own activities: an open session a coursemate can be joined in leads, a recruiting ping raises one further, then whatever the course's next Mission points at, and a finished activity sinks without disappearing. One shared score means the course page and the map cannot drift apart as its weights are tuned.

Three things differ from the map, each following from where the row sits:

- **A session the learner already holds a role in is filtered out of the row.** The row suggests what to start next; a session already under way is resumed from the course's Chats section.
- **The relevance band is this course's own**, never the map's cross-quest sum — a course surface reads only its own course's progress (the per-course scoping rule above).
- **The map's first-map penalty, its dismissal penalty and its recency term do not apply.** A course's activities were hand-picked by its author, so a 3+ role one is part of the syllabus rather than a newcomer's dead end; there is no large card here to dismiss; and the row has no per-session start time to decay, so a learner reading the page does not watch it reorder itself.

The row holds the top five and scrolls. Equal scores break on a stable key, so a rebuild never reshuffles it under a reader. It renders nothing at all only when every activity in the plan is a session the learner is already in.

## Activity cards on the course plan panel

The course plan panel lists the course's activities as cards, in rows. Each card carries the activity image, name, a **star row**, and the activity type next to the role count.

**The star row**: the learner's earned stars for that activity (best single session, per the rollup above) out of the activity's earnable count — its goals-per-role count, falling back to the min across roles (org [`activities`](../../../.github/.github/instructions/activities.instructions.md) doc owns that number).

**Card states** — so a learner can scan a course listing and tell what each activity is doing right now ([Figma mockup](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13765-270419&t=pnytLg8wuPthDfDt-11)):

1. **Normal (not started)** — 🔘 light gray card: image, name, star row, activity type + role count.
2. **Joinable/Open** — 🟢 green card with an overlay tag "Open (N)" on the top right in white text, where N is the number of open sessions to choose from. The tag states the meaning in text (screen-reader friendly rather than color-only); the green matches the joinable map pin (V6).
3. **Ongoing** — 🟣 purple card with an "Ongoing" overlay tag on the top right in white text; same text-not-color-only rationale; the purple matches the ongoing map pin (V6).
4. **Needs more participants to start** — 🔘 light gray card at 30% opacity: still clickable but de-emphasized. Tapping it explains why ("Uh oh, you need to invite N people…").

## Per-course activity pinning

The design — what a pin means, why it lives in course state and never the quest plan, attribution-level semantics — is the org doc's [Per-course activity pinning](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md#per-course-activity-pinning). This doc records the client mechanics ([client#7748](https://github.com/pangeachat/client/issues/7748)):

- The pin travels on the course space's teacher-mode state (`TeacherModeModel.pinnedActivitiesByObjective`: Mission id → pinned `activity_id` content ids). Null, a missing Mission key, or an empty list all mean unrestricted.
- Restriction is a **pure copy** at the outline boundary (`QuestOutline.restrictedTo`) — never a mutation of the quest-outline cache, which is shared across courses referencing the same quest; that copy is what lets the same quest run restricted in one course and open in another.
- **One rule, one home**: `effectivePinnedActivityIds` carries the fail-open rule (no pin, empty pin, or an all-stale pin → unrestricted, so a pin can never make a Mission unsatisfiable). Both the outline restriction and the course-scoped map's marker filter call it. The world-scoped map is deliberately never filtered — everything stays playable everywhere.
- The resolver is **pin-unaware by construction**: star attribution and the effective-threshold clamp both derive from the outline's per-Mission activity sets, so a filtered outline scopes attribution and clamps against the pinned set with no resolver changes. This holds only because totals are per course (above) — a cross-course rollup would re-admit the very activities the pin excluded ([client#7771](https://github.com/pangeachat/client/issues/7771)).
- Previews and non-joined contexts pass no pins — there is no learner progress to scope, and fail-open is the default everywhere.
- The teacher editing surface is deferred to the admin panel ([admin-dash#30](https://github.com/pangeachat/admin-dash/issues/30)); until it ships, pins are written to course room state directly.

## Future Work

File GitHub issues for these and link them here.

- A persisted per-Mission star total (server-side rollup) once reading every session room client-side becomes too costly at catalog scale.
- Teacher-set **hard** restrictions (an opt-in gate on top of the soft default), if classroom demand appears — deliberately not built today (see the org doc). Distinct from per-course activity pinning (above), which is built and restricts *which activities satisfy*, not *when Missions are reachable*.
- Implement the joinable/open activity card design — [pangeachat/client#7669](https://github.com/pangeachat/client/issues/7669).
- Design hint indicating an activity needs more people to start — [pangeachat/client#6810](https://github.com/pangeachat/client/issues/6810).
