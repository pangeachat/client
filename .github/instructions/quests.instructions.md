---
applyTo: "lib/features/quests/**,lib/features/course_plans/**,lib/routes/courses/course_objectives/**"
description: "Client-side next-Mission resolver — the one shared answer to 'which Mission should this learner work on next, per quest?', what fills a Mission (XP from its activities and its vocabulary's practice), the star and sparkle vocabulary, and the course page's Learning Objective section."
---

# Quests & Learning-Objective Progression (Client)

A **Quest** is the learner's ordered journey through **Learning Objectives** (learner-facing label: **Missions**). The cross-repo model — what a Mission is, and the rule that progression is **soft** (an ordered suggestion that only *ranks* content, never locks it) — lives in the org doc [`quests-and-learning-objectives`](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md). This doc owns the **client-side resolver**: how the app computes, from data it already holds, each quest's **next Mission** — the single ranking input the world map and other surfaces preference toward — and what the learner sees of it on the course page.

## Stars and sparkles

Two marks, and they never share a glyph ([client#9420](https://github.com/pangeachat/client/issues/9420)):

- A **star** (five points) is a **completed Mission**. The analytics bar's star count is the number of Missions the learner has completed; its page lists them ([activities.instructions.md](activities.instructions.md), "The Learning Objectives list").
- A **sparkle** (four points, [`SparkleIcon`](../../lib/widgets/sparkle_icon.dart)) is one **orchestrator-awarded activity goal**. Activity cards, chat rows, the in-session goal header and the start page count goals in sparkles.

Teachers asked for this split: a count of activity goals said little about what a student can *do*, while a Mission is a can-do statement. The one place the old quantity survives is a member's **banked total** on the course Leaderboard ([course-leaderboard.instructions.md](course-leaderboard.instructions.md)): it is still the goals they have banked across everything they have played, published on their profile ([profile.instructions.md](profile.instructions.md)), and it is drawn as a sparkle so it cannot be read as Missions.

## What fills a Mission

A Mission has an **XP meter**. It fills from three sources and is **complete — one star — when its XP reaches the threshold**:

- **Session XP.** Every construct use the learner earns in a session room of one of the Mission's activities, summed over *every* session of it. Repeat sessions accumulate: XP is effort, so a replay still moves the meter.
- **The sparkle bonus.** Each session's XP is raised by `kSparkleXpBonus` (10%) per goal the learner earned in it, so three sparkles make a session count for 1.3× its XP. Goals keep guiding the conversation and reward it a little; they no longer gate anything ([client#9439](https://github.com/pangeachat/client/issues/9439)).
- **Practice XP on the Mission's vocabulary.** The Mission's target vocabulary is every suggested-vocab entry across its activities. XP from standalone practice on one of those words counts toward the Mission.

**The practice attribution is a stopgap, to be replaced.** A standalone practice use records no room and no Mission, and recording one would change the stored construct-use schema, which this first cut deliberately leaves alone. Until a use carries the Mission it was launched for, practising a Mission's words *anywhere* counts toward it, and a word two Missions share credits both. Session XP and practice XP are a partition of the learner's uses (a use either names a room or it does not), so nothing is counted twice.

**The threshold** is `kDefaultXpToCompleteObjective` (300 XP) unless the course sets its own — the teacher's **XP per Mission** setting in the course's More section, stored in course-space room state as `xpToCompleteObjective`. The old stars-per-Mission override is still parsed and ignored, so a stored "10 stars" is never read as "10 XP". There is no content ceiling: XP is unbounded, so every Mission with an activity is completable.

Session XP lives in the local analytics database, not room state ([analytics-system.instructions.md](analytics-system.instructions.md)). [`MissionXpCache`](../../lib/features/quests/mission_xp_cache.dart) holds the learner's XP grouped by room and, for room-less uses, by lemma; it re-reads on construct updates and language changes, and every resolver reads from it. [`Client.userXpByActivity`](../../lib/features/quests/quests_client_extension.dart) rolls the by-room map up to activities with the sparkle bonus applied. A read before the first refresh lands sees empty maps and every Mission as unstarted — the same fail-soft as a missing outline.

## One shared resolver

Nothing is locked, so the question is not "is this allowed?" but "where should the learner go next?" — and that is asked by many surfaces, so it is resolved **once** into a single shared answer, never re-derived per surface (re-deriving invites two surfaces drifting on the same question). It is built from inputs the client already holds:

- **The ordered Mission sequences** of the learner's in-scope quests — their joined courses by default, or whatever the world map's quest filter selects — each quest's outline (ordered Mission ids, the activities under each, and each Mission's vocabulary), cached and rebuilt on course join/leave.
- **The per-Mission XP rollup** above.

From those, the resolver finds each quest's **anchor (next) Mission**: the **first Mission in quest order whose XP is below the threshold**. A quest whose every Mission is complete has **no anchor at all** ([client#8997](https://github.com/pangeachat/client/issues/8997)): there is no next step to name, and naming the weakest Mission anyway pointed a finished learner back at work they had already completed. When several quests are in scope it yields, **per quest**, an anchor and that quest's own per-Mission XP; consumers preference still-incomplete Missions and **accumulate** across quests (so an activity advancing several quests' unfinished Missions ranks higher) — the resolver just supplies the anchors and totals, the weighting lives in the consumer (see the [world map](world-map.instructions.md) Priority matrix).

**Progression totals are per course, never blended across them** ([client#7771](https://github.com/pangeachat/client/issues/7771)). Missions are a shared catalog reused across quests, so two joined courses routinely carry the same Mission with *different* activities. A Mission's XP only means something against the activity set it was summed over: rolling several courses together would credit one course's XP to another's content and silently undo that course's activity pins. Accumulation across quests is the *consumer's* job (the map's band), not a property of the totals. Where two courses genuinely list the **same** activity, each counts it once on its own — that needs no merging, since both outlines carry it. The star *count*, by contrast, is the learner's: a Mission complete in two courses is one star.

**Fail soft.** A surface that asks before the resolver is built simply has no anchor yet and ranks on plain relevance — a cold open (e.g. an activity link opened without visiting the map first) is never blocked, because nothing is ever blocked. The resolver only sharpens ordering; its absence degrades to neutral ranking, not to a wall.

## Consumed by

Every surface that preferences by progression reads the *same* shared resolver, so the answer is consistent and computed once:

- the [world map](world-map.instructions.md) — the Priority matrix raises activities carrying the anchor Mission to the top of the relevance band, decaying for Missions further along; per-activity sparkle progress renders as a fill (see its pin-display section). The map's pins manager resolves first in a session and publishes to the shared answer, which is what puts a star count on the analytics bar before any course page has been opened;
- the **activity start page** — opens directly into play for every activity (nothing is gated), showing sparkle progress and, where relevant, that this is a next-Mission activity;
- the **course page's Learning Objective section** and its progress bars (below);
- the **analytics bar's star count** and the Learning Objectives page;
- the course/quest list, as it is built for v3.

## Progress display on the course page

The course page tells the learner how far along they are, read from the same shared resolver the map uses — one answer, never re-derived per surface — **scoped to the course being viewed** (above). A course it can't resolve (a preview, or before the resolution lands) shows a muted empty bar rather than another course's numbers.

- **The Mission meter** — the course page's Learning Objective section meters the Mission on show (the circle the learner picked, else the anchor); the collapsed mobile peek meters the anchor. XP over the threshold, as a bar with the exact count on hover or tap ("120 of 300 XP toward this objective"). When the course is complete the peek's bar reads full.
- **Per Mission, on the full plan** — each Mission header shows its XP over its threshold, with no mark while in progress and the gold star once complete. Surplus shows raw (340 / 300 XP); only the bar clamps.
- **The Mission circles** — one numbered circle per Mission in plan order, under the course page's language and level chips and at the top of the full plan: a check for a complete Mission, a tint on the current one, a bold ring around the one on show, a plain number for the rest; each carries its statement as a tooltip. On the course page a tap shows that Mission in the Learning Objective section — the circles are a switcher, and the plan stays behind "See all". The full plan has no bar of its own: the circles already say how many Missions are complete, and a second star bar there read as a second quantity. A Mission with no activities is not a circle ([client#7114](https://github.com/pangeachat/client/issues/7114)). A row too long for the panel wraps.

A course **preview** (not joined) shows no progress — there is no learner progress to show. The course page shows no activity count beside its progress ([client#9390](https://github.com/pangeachat/client/issues/9390)): a count beside a goal read as a second requirement.

## Who made the course

The course page credits its quest's **owner** — whoever built the course plan. That is a different fact from who administers the room, and the room has its own surface for that (the Leaderboard's admin line): a teacher who starts a class from a catalog quest administers a course Pangea wrote, and the credit says so.

The owner is stored on the quest row as `owner_mxid`, a plain-text Matrix id the client reads verbatim. Nothing resolves it on the client's behalf. The `owner` field beside it is a per-environment `matrix-users` row id, and that collection is service- and admin-read only, so a learner's token can read the quest and never resolve the person behind it — which is why the Matrix id is stored where the consumer reads it rather than joined on by a service at read time. Name and avatar then come from that owner's own Matrix profile, so a teacher controls their own credit by editing their profile and we keep no second copy of their name.

Same ladder as an activity's credit, which [activity-start-page.instructions.md](activity-start-page.instructions.md) owns: profile, else the stored Matrix id beside a placeholder contact icon, and the PangeaChat name and avatar reserved for content owned by `@system:pangea.chat`. **A quest with no owner recorded is not evidence Pangea made it.** Content that is genuinely Pangea's says so with the system Matrix id, exactly as an activity does; an unrecorded owner is an unanswered question, and the surface shows no credit at all rather than a guessed one. The failure that ordering prevents — a teacher's course carrying Pangea's name — is worse than an uncredited one.

**Where the credit shows turns on whether the course exists yet.**

- **While the course is being made** — the client's create-course page and the dashboard's setup wizard — it is **prominent**. Someone choosing a plan to build their class on is deciding partly on who made it, so the credit belongs in the decision.
- **Once the course exists** — the course page's **More** section, among the course's other details. It is deliberately not at the top of the panel the way an activity's credit leads its start page. That page *is* the one activity's header; a course page opens on the teacher's own description of their class, and a credit directly under it reads as a banner over their words — the more so on the common catalog path, where the quest is Pangea's and the class is theirs.

Missions are **not** attributed. They are generic and reused across courses and languages by design, carry no owner, and crediting one to whoever first minted it would misrepresent shared content as authored.

## The Learning Objective section on the course page

The course page opens on the learner's **current Mission** ([client#9437](https://github.com/pangeachat/client/issues/9437)), headed **Learning Objective** with the star glyph: its place in the plan ("Mission 3 of 8"), its can-do statement, its meter, then one row of cards. A tap on a Mission circle shows that Mission here instead — statement, meter and row — and the ring moves to it; the current Mission keeps its tint. The row is — a **Practice** tile first ([client#9438](https://github.com/pangeachat/client/issues/9438)), then the Mission's activities. The Mission-by-Mission plan — every Mission with its statement, its XP and its activities — sits one tap away behind the section header's "See all", and is where a learner reads the course's shape.

The row is the Mission's whole content, ranked by the **same [Priority matrix](world-map.instructions.md#priority-matrix) the world map ranks pins by**: an open session a coursemate can be joined in leads, a recruiting ping raises one further. One shared score means the course page and the map cannot drift apart as its weights are tuned. Three things differ from the map, each following from where the row sits:

- **A session the learner already holds a role in is filtered out of the row.** The row suggests what to start next; a session already under way is resumed from the course's Chats section.
- **A finished activity stays in the row, last.** The row is not a shortlist of what is new but the Mission's content, and a replay still earns XP toward it; its check overlay says it is done. (The earlier shortlist dropped finished activities, [client#8901](https://github.com/pangeachat/client/issues/8901); that rule ends with the shortlist.)
- **The map's first-map penalty, its dismissal penalty and its recency term do not apply.** A course's activities were hand-picked by its author, so a 3+ role one is part of the syllabus rather than a newcomer's dead end; there is no large card here to dismiss; and the row has no per-session start time to decay, so a learner reading the page does not watch it reorder itself.

Equal scores break on a stable key, so a rebuild never reshuffles the row under a reader. Before the course's progress resolves, the section shows the plan's first Mission, so a cold open still shows a place to start.

**When every Mission is complete** there is no current Mission to show; unless a circle is tapped, the section shows a **course complete** card instead — the count of objectives done and a Practice button for the learner's usual session — and the meter reads full. The full plan behind "See all" still lists every Mission, each with its check.

**The Practice tile** opens vocabulary practice scoped to the Mission ([practice-exercises.instructions.md](practice-exercises.instructions.md), "Objective practice"); the XP earned there reaches the Mission through its vocabulary, above.

## Activity cards on the course plan panel

The course plan panel lists the course's activities as cards, in rows. Each card carries the activity image, name, a **sparkle row**, and the activity type next to the role count.

**The sparkle row**: the learner's earned goals for that activity (best single session) out of the activity's earnable count — its goals-per-role count, falling back to the min across roles (org [`activities`](../../../.github/.github/instructions/activities.instructions.md) doc owns that number).

**Card states** — so a learner can scan a course listing and tell what each activity is doing right now ([Figma mockup](https://www.figma.com/design/n2qX4WsnVhYqT2KV6pMVbl/Everything-outside-of-Chat?node-id=13765-270419&t=pnytLg8wuPthDfDt-11)):

1. **Normal (not started)** — 🔘 light gray card: image, name, sparkle row, activity type + role count.
2. **Joinable/Open** — 🟢 green card with an overlay tag "Open (N)" on the top right in white text, where N is the number of open sessions to choose from — the sessions this course lists, not every joined course's ([world-map.instructions.md](world-map.instructions.md), Discovering joinable sessions). The tag states the meaning in text (screen-reader friendly rather than color-only); the green matches the joinable map pin (V6).
3. **Ongoing** — 🟣 purple card with an "Ongoing" overlay tag on the top right in white text; same text-not-color-only rationale; the purple matches the ongoing map pin (V6).
4. **Needs more participants to start** — 🔘 light gray card at 30% opacity: still clickable but de-emphasized. Tapping it explains why ("Uh oh, you need to invite N people…").

## Mission header states on the course plan

Each Mission's header on the full course plan tells the learner at a glance whether it is done, next, or later ([client#8874](https://github.com/pangeachat/client/issues/8874) — before this, the only mark was the statement's text colour, which nobody could see). Three states:

- **Up next** — the shared resolver's anchor for this course. Its header carries an "Up next" label, and its statement and XP count take the `primary` accent; the label says the state in words, so it is never colour alone. Nothing wraps the section: a band or an outline around header and cards was tried and dropped, because a tint shows the carousel's surface-coloured scroll-arrow strip as a notch and any inset throws the section's margins off against its neighbours. At most one Mission per course wears it, and a complete Mission never does — once the whole course is complete there is no anchor, so no Mission carries the label ([client#8997](https://github.com/pangeachat/client/issues/8997)).
- **Complete** — XP at or past the threshold. The gold star appears before the count — it is the star the Mission earned, and it shows nowhere before then, since a star beside an XP count in progress read as "257 of 300 stars" — and the header text drops to `onSurfaceVariant`, so finished work reads as done without disappearing: its activities stay in view and playable, since a learner can still raise its XP.
- **Later** — everything else, plain.

The emphasis lives on the Mission header alone, never on the section or its activity cards: the card states above keep their meaning under an Up-next header.

## Per-course activity pinning

The design — what a pin means, why it lives in course state and never the quest plan, attribution-level semantics — is the org doc's [Per-course activity pinning](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md#per-course-activity-pinning). This doc records the client mechanics ([client#7748](https://github.com/pangeachat/client/issues/7748)):

- The pin travels on the course space's teacher-mode state (`TeacherModeModel.pinnedActivitiesByObjective`: Mission id → pinned `activity_id` content ids). Null, a missing Mission key, or an empty list all mean unrestricted.
- Restriction is a **pure copy** at the outline boundary (`QuestOutline.restrictedTo`) — never a mutation of the quest-outline cache, which is shared across courses referencing the same quest; that copy is what lets the same quest run restricted in one course and open in another.
- **One rule, one home**: `effectivePinnedActivityIds` carries the fail-open rule (no pin, empty pin, or an all-stale pin → unrestricted, so a pin can never make a Mission uncompletable). Both the outline restriction and the course-scoped map's marker filter call it. The world-scoped map is deliberately never filtered — everything stays playable everywhere.
- The resolver is **pin-unaware by construction**: XP attribution and a Mission's vocabulary both derive from the outline's per-Mission activity sets, so a filtered outline scopes both with no resolver changes. This holds only because totals are per course (above) — a cross-course rollup would re-admit the very activities the pin excluded ([client#7771](https://github.com/pangeachat/client/issues/7771)).
- Previews and non-joined contexts pass no pins — there is no learner progress to scope, and fail-open is the default everywhere.
- The teacher editing surface is deferred to the admin panel ([admin-dash#30](https://github.com/pangeachat/admin-dash/issues/30)); until it ships, pins are written to course room state directly.

## Future Work

File GitHub issues for these and link them here.

- **Record the Mission on a practice use**, so practice XP is credited to the Mission it was launched for and the by-lemma stopgap above can go ([client#9420](https://github.com/pangeachat/client/issues/9420)).
- A persisted per-Mission XP total (server-side rollup) once reading every session room and the local analytics database client-side becomes too costly at catalog scale.
- Teacher-set **hard** restrictions (an opt-in gate on top of the soft default), if classroom demand appears — deliberately not built today (see the org doc). Distinct from per-course activity pinning (above), which is built and restricts *which activities count*, not *when Missions are reachable*.
- Implement the joinable/open activity card design — [pangeachat/client#7669](https://github.com/pangeachat/client/issues/7669).
- Design hint indicating an activity needs more people to start — [pangeachat/client#6810](https://github.com/pangeachat/client/issues/6810).
