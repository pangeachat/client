---
applyTo: "lib/features/quests/**,lib/features/course_plans/**,lib/routes/courses/course_objectives/**"
description: "Client-side next-Mission resolver — the one shared answer to 'which Mission should this learner work on next, per quest?', what fills a Mission (activity XP from saved sessions, goals, and practice on its words), the star and goal-diamond vocabulary, and the course page's Mission circles and Mission card."
---

# Quests & Learning-Objective Progression (Client)

A **Quest** is the learner's ordered journey through **Learning Objectives** (learner-facing label: **Missions**). The cross-repo model — what a Mission is, and the rule that progression is **soft** (an ordered suggestion that only *ranks* content, never locks it) — lives in the org doc [`quests-and-learning-objectives`](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md). This doc owns the **client-side resolver**: how the app computes, from data it already holds, each quest's **next Mission** — the single ranking input the world map and other surfaces preference toward — and what the learner sees of it on the course page.

## Stars and goal diamonds

Two marks, and they never share a glyph ([client#9420](https://github.com/pangeachat/client/issues/9420)):

- A **star** marks a **Mission**. It is there from the moment the Mission appears — outlined while the Mission is in progress, filled gold once it is complete — so completion changes the star's state, never whether it is there ([`MissionStar`](../../lib/routes/courses/course_objectives/mission_star.dart)). The analytics bar's star count is the number of Missions the learner has completed; its page lists them ([activities.instructions.md](activities.instructions.md), "The Learning Objectives page"). There is no per-activity star.
- A **goal diamond** marks one **orchestrator-awarded activity goal**, worth a flat `kGoalXp` (100 XP) of activity XP ([`GoalDiamond`](../../lib/widgets/goal_diamond.dart)): gold and filled once earned, an outline while open. Activity cards, chat rows, the in-session goal header and the start page count goals in diamonds. A diamond is neither a star (a Mission), the double-ring stamp (a saved activity, [world-map.instructions.md](world-map.instructions.md), "Played stamps") nor a sparkle (XP).

Teachers asked for this split: a count of activity goals said little about what a student can *do*, while a Mission is a can-do statement. The one place the old quantity survives is a member's **banked total** on the course Leaderboard ([course-leaderboard.instructions.md](course-leaderboard.instructions.md)): it is still the goals they have banked across everything they have played, published on their profile ([profile.instructions.md](profile.instructions.md)), and it is drawn as a goal diamond so it cannot be read as Missions.

## What fills a Mission

A Mission is complete — its star fills — when the **XP earned under it** reaches the course's **threshold** (org [quests-and-learning-objectives](../../../.github/.github/instructions/quests-and-learning-objectives.instructions.md), "Progression is soft"). XP under a Mission is the **activity XP** of each of its activities, summed, plus the practice done on its words:

- **Activity XP** counts the learner's **saved** sessions of the activity. Each session contributes the chat XP earned in its room — the construct-use XP the client already mints per message ([analytics-system.instructions.md](analytics-system.instructions.md)) — plus a flat `kGoalXp` per goal the learner was awarded there, plus the practice done in that room (below). Repeat sessions accumulate: XP is effort, and the per-construct XP cap is the only farming guard. **A session counts only once it is saved** — finishing the activity banks it, so the course page's meter moves when a session ends; while it runs, the goal header's ring shows the session's XP toward what its Mission still needs ([activities.instructions.md](activities.instructions.md), "The goal header").
- **Practice credit.** A practice use that names a session room — the toolbar practice on a message, a practice session launched from a completed session — credits that room. Practice outside any session — the Mission card's Practice, the Learning Objectives page's, the analytics page's — names no room and counts toward **every Mission whose word list holds the practised word**, whether or not the learner ever used the word in a session. A Mission's **word list** is every suggested-vocab entry across its activities in this course, once per lemma (`QuestObjectiveGroup.lemmas`), matched case-folded. So a correct answer on a word the learner has never used adds it to their vocabulary, earns its practice XP, and counts toward the Mission in the same stroke. A word two Missions share counts toward both. [`MissionXpCache`](../../lib/features/quests/mission_xp_cache.dart) keeps the learner's in-room XP by room and their room-less practice XP by lemma, read from the local analytics database and re-read on construct updates and language changes; the resolver adds the word-list practice to the Mission's activity XP. A read before the first refresh lands sees no XP and every Mission as unstarted — the same fail-soft as a missing outline.
- **Where it came from.** Every surface that shows a Mission's XP splits it three ways — **chats** (XP from the learner's own messages in its saved sessions), **goals** (`kGoalXp` per goal diamond) and **practice** (practice in its sessions plus practice on its words) — drawn as three golds of one ring, apart by lightness ([`MissionRingPalette`](../../lib/routes/courses/course_objectives/mission_xp_ring.dart)), with a legend of the three numbers. The split (`Client.missionXpBreakdown`) reads the same inputs as the resolver's total, so the ring and the XP count it surrounds agree.
- **The threshold** is the course's **XP per objective**, which the instructor sets in the admin dashboard from presets that describe what a student does to reach each, or as a custom value (org doc, "XP per objective"). It travels in course-space room state as `xpToCompleteObjective`; the client only reads it, and defaults to the Standard preset, `kDefaultXpToCompleteObjective` (1,600 XP), when a course has none. The earlier stars-per-Mission value is still parsed and ignored, so a stored "10 stars" is never read as "10 XP". There is no content ceiling: XP is unbounded, so every Mission with an activity is completable at any threshold.

## One shared resolver

Nothing is locked, so the question is not "is this allowed?" but "where should the learner go next?" — and that is asked by many surfaces, so it is resolved **once** into a single shared answer, never re-derived per surface (re-deriving invites two surfaces drifting on the same question). It is built from inputs the client already holds:

- **The ordered Mission sequences** of the learner's in-scope quests — their joined courses by default, or whatever the world map's quest filter selects — each quest's outline (ordered Mission ids and the activities under each), cached and rebuilt on course join/leave. The order comes from the quest row, read from the CMS directly; each Mission's statement and the activity cards come from choreo's course outline read in the learner's resolved display language (L2 when "App in target language" is on, else L1), and the outline is re-read when that language changes ([client#8577](https://github.com/pangeachat/client/issues/8577), [#9151](https://github.com/pangeachat/client/issues/9151)). The client never reads `learning-objectives` from the CMS: a direct read returns canonical text only (org doc § Content access and localization).
- **The per-Mission XP rollup** above, read from the course's own list of Missions and activities — its copy, else its pins — the same view the course page shows.

From those, the resolver finds each quest's **anchor (next) Mission**: the **first Mission in quest order whose XP is below the threshold**. A quest whose every Mission is complete has **no anchor at all** ([client#8997](https://github.com/pangeachat/client/issues/8997)): there is no next step to name, and naming the weakest Mission anyway pointed a finished learner back at work they had already completed. When several quests are in scope it yields, **per quest**, an anchor and that quest's own per-Mission XP; consumers preference still-incomplete Missions and **accumulate** across quests (so an activity advancing several quests' unfinished Missions ranks higher) — the resolver just supplies the anchors and totals, the weighting lives in the consumer (see the [world map](world-map.instructions.md) Priority matrix).

**Progression totals are per course, never blended across them** ([client#7771](https://github.com/pangeachat/client/issues/7771)). Missions are a shared catalog reused across quests, so two joined courses routinely carry the same Mission with *different* activities. A Mission's XP only means something against the activity set it was summed over: rolling several courses together would credit one course's XP to another's content and silently undo that course's activity pins. Accumulation across quests is the *consumer's* job (the map's band), not a property of the totals. Where two courses genuinely list the **same** activity, each counts it once on its own — that needs no merging, since both outlines carry it. The star *count*, by contrast, is the learner's: a Mission complete in two courses is one star.

**Fail soft.** A surface that asks before the resolver is built simply has no anchor yet and ranks on plain relevance — a cold open (e.g. an activity link opened without visiting the map first) is never blocked, because nothing is ever blocked. The resolver only sharpens ordering; its absence degrades to neutral ranking, not to a wall.

## Consumed by

Every surface that preferences by progression reads the *same* shared resolver, so the answer is consistent and computed once:

- the [world map](world-map.instructions.md) — the Priority matrix raises activities carrying the anchor Mission to the top of the relevance band, decaying for Missions further along; per-activity goal progress renders as a fill (see its pin-display section). The map's pins manager resolves first in a session and publishes to the shared answer, which is what puts a star count on the analytics bar before any course page has been opened;
- the **activity start page** — opens directly into play for every activity (nothing is gated), showing goal progress and, where relevant, that this is a next-Mission activity;
- the **course page's Mission circles and Mission card**, and the collapsed course bar's circles (below);
- the **analytics bar's star count** and the Learning Objectives page;
- the course/quest list, as it is built for v3.

## Progress display on the course page

The course page tells the learner how far along they are, read from the same shared resolver the map uses — one answer, never re-derived per surface — **scoped to the course being viewed** (above). A course it can't resolve (a preview, or before the resolution lands) shows empty rings rather than another course's numbers.

**The Mission circles** ([`ObjectiveProgressCircles`](../../lib/routes/courses/course_objectives/objective_progress_circles.dart)) — one numbered circle per Mission in plan order, under the course page's language and level chips. Each sits inside a gold ring of its XP toward its star. A complete Mission is its star, gold; the current Mission (the anchor) is tinted; the rest are plain numbers, drawn a little lighter. A pointer under one circle marks the **Mission on show**. A tap shows that Mission — the circles are a switcher. The row never wraps: it scrolls, with the Activities row's arrows over whichever end it can still move toward, and opens scrolled so the Mission on show is in view. Each circle carries its statement as a tooltip and its state in its accessible name, so neither the colour nor the number is the only carrier. A Mission with no activities is not a circle ([client#7114](https://github.com/pangeachat/client/issues/7114)).

Two more marks ride the circles:

- **Class location** — where the teacher's due dates put the class: the first Mission in plan order still due, else, every dated Mission past, the last dated one. A muted grey bubble reading "Class location" sits above that circle, its pointer turned down onto it — quieter than the learner's own pointer, so it reads as the class's mark rather than theirs. A course with no due dates shows none. The due dates are the teacher's, set from the admin dashboard and carried in the course's own copy of its Mission list (`pangea.course_missions`); a due date never blocks, hides or locks anything.
- **A ping bell** — on a Mission other than the one on show, when a coursemate has pinged one of its sessions and the session is still open to join. The course map shows only the Mission on show ([world-map.instructions.md](world-map.instructions.md), "The Mission on show"), so the bell is how a learner hears about a session elsewhere in the course.

**The Mission on show** is the circle the learner picked, else the anchor, else — before progress resolves — the plan's first Mission. It rides the URL (`?mission=`), so the course page, the collapsed course bar and the course map always show the same Mission. Picking another course drops it; a picked id the course no longer carries falls back to the anchor.

**At the course panel's floor** — the wide context bar ([world-map.instructions.md](world-map.instructions.md), "The course context bar") and the narrow peek — the same circles show with the Mission on show named under its pointer ("Mission 3"), since no Mission card is in view to say it. The row keeps a fixed height whether or not its circles have loaded, so the bar never jumps when the plan arrives.

A course **preview** (not joined) shows no progress — there is no learner progress to show. The course page shows no activity count beside its progress ([client#9390](https://github.com/pangeachat/client/issues/9390)): a count beside a goal read as a second requirement.

## Who made the course

The course page credits its quest's **owner** — whoever built the course plan. That is a different fact from who administers the room, and the room has its own surface for that (the Leaderboard's admin line): a teacher who starts a class from a catalog quest administers a course Pangea wrote, and the credit says so.

The owner is stored on the quest row as `owner_mxid`, a plain-text Matrix id the client reads verbatim. Nothing resolves it on the client's behalf. The `owner` field beside it is a per-environment `matrix-users` row id, and that collection is service- and admin-read only, so a learner's token can read the quest and never resolve the person behind it — which is why the Matrix id is stored where the consumer reads it rather than joined on by a service at read time. Name and avatar then come from that owner's own Matrix profile, so a teacher controls their own credit by editing their profile and we keep no second copy of their name.

Same ladder as an activity's credit, which [activity-start-page.instructions.md](activity-start-page.instructions.md) owns: profile, else the stored Matrix id beside a placeholder contact icon, and the PangeaChat name and avatar reserved for content owned by `@system:pangea.chat`. **A quest with no owner recorded is not evidence Pangea made it.** Content that is genuinely Pangea's says so with the system Matrix id, exactly as an activity does; an unrecorded owner is an unanswered question, and the surface shows no credit at all rather than a guessed one. The failure that ordering prevents — a teacher's course carrying Pangea's name — is worse than an uncredited one.

**Where the credit shows turns on whether the course exists yet.**

- **While the course is being made** — the client's create-course page and the dashboard's setup wizard — it is **prominent**. Someone choosing a plan to build their class on is deciding partly on who made it, so the credit belongs in the decision.
- **Once the course exists** — the course page's **More** section, among the course's other details. It is deliberately not at the top of the panel the way an activity's credit leads its start page. That page *is* the one activity's header; a course page opens on the teacher's own description of their class, and a credit directly under it reads as a banner over their words — the more so on the common catalog path, where the quest is Pangea's and the class is theirs.

Missions are **not** attributed. They are generic and reused across courses and languages by design, carry no owner, and crediting one to whoever first minted it would misrepresent shared content as authored.

## The Mission card

Under the circles, the course page opens on the **Mission card** for the Mission on show ([`MissionCard`](../../lib/routes/courses/course_objectives/mission_card.dart), [client#9437](https://github.com/pangeachat/client/issues/9437)). It is the course's main content, on the panel's own surface with a brand-purple edge and a hard lip below it, and it carries, top to bottom:

1. A **"Mission N"** pill.
2. The Mission's **star and can-do statement** — never larger than the course title above the card.
3. The **XP ring**, split by source, with the XP left to the star ("1,531 XP to your star", or "Star earned!") and the legend beside it.
4. **Play** — one large primary button, pulsing gently while the Mission is unfinished (still under reduced motion). It opens the best next thing to do for this Mission:
   - a session the learner already holds a role in **among this Mission's activities** — Play reads **Continue**, names the activity under its label, and reopens the session's chat, so a started activity gets finished before a new one starts;
   - otherwise the top of the Mission's activity row (below) — a coursemate's open session first, else the best activity to start;
   - otherwise, every activity being finished, the Mission's first activity for another round.

   Each Mission keeps to its own activities: a session from another Mission is resumed from that Mission's card or from Chats.
5. **Practice**, with the Mission's word count beside it — vocabulary practice on this Mission's word list ([practice-exercises.instructions.md](practice-exercises.instructions.md), "Objective practice"). It counts toward the Mission through its words ("Practice credit", above).
6. **Activities** — the Mission's activity row, inside the card, because those activities are what fill it.

**The activity row** is the Mission's whole content, ranked by the **same [Priority matrix](world-map.instructions.md#priority-matrix) the world map ranks pins by**: a session the learner is in leads, then an open session a coursemate can be joined in, a recruiting ping raising one further. One shared score means the course page and the map cannot drift apart as its weights are tuned. Three things differ from the map, each following from where the row sits:

- **The learner's own unfinished sessions stay in the row and lead it**, so Continue and the card it continues are the same thing.
- **A finished activity is filtered out** ([client#8901](https://github.com/pangeachat/client/issues/8901), [client#9470](https://github.com/pangeachat/client/issues/9470)) unless a session of it is live — a coursemate's open session on it is still something to join, and a replay still earns XP.
- **The map's first-map penalty, its dismissal penalty and its recency term do not apply.** A course's activities were hand-picked by its author, so a 3+ role one is part of the syllabus rather than a newcomer's dead end; there is no large card here to dismiss; and the row has no per-session start time to decay, so a learner reading the page does not watch it reorder itself.

Equal scores break on a stable key, so a rebuild never reshuffles the row under a reader. A tap on a card whose session the learner is in reopens that chat; any other card opens the activity's start page.

**The full course plan** — every Mission with its statement, its XP and its activities ("Mission header states on the course plan", below) — sits behind a quiet **"See full course plan"** link under the Mission card. It is for reading the course's shape, which educators asked to see, rather than for choosing what to do next, so it is a plain text link rather than a button and never competes with Play.

**When every Mission is complete** there is no current Mission to show; unless a circle is tapped, the page shows a **course complete** card instead of the Mission card — the count of objectives done and a Practice button for the learner's usual session. The circles above it show every Mission's star.

## Activity cards

Every surface that lists a course's activities draws the same card ([`ActivitySuggestionCard`](../../lib/routes/chat/chat_details/activity_suggestion_card.dart)): the activity image, name, a **goal-diamond row**, and the activity type next to the role count. The map's large pins are a squashed version of the same card ([world-map.instructions.md](world-map.instructions.md)).

**The goal-diamond row**: the learner's earned goals for that activity (best single session) out of the activity's earnable count — its goals-per-role count, falling back to the min across roles (org [`activities`](../../../.github/.github/instructions/activities.instructions.md) doc owns that number).

**Card states** — so a learner can scan a course listing and tell what each activity is doing right now. A live state is a **frame and a corner tab**, never a fill, so the card's own content stays the same in every state; the colours match the map pins ([world-map.instructions.md](world-map.instructions.md), "Pin state"):

1. **Normal (not started)** — the plain card.
2. **Joinable/Open** — a green frame with an "Open (N)" tab in the top-left corner, where N is the number of open sessions to choose from — the sessions this course lists, not every joined course's ([world-map.instructions.md](world-map.instructions.md), Discovering joinable sessions). The tab states the meaning in text, so the state is never colour alone.
3. **Ongoing** — a purple frame and tab ("Ongoing"); a session still filling its seats shows its participant row under the tab.
4. **Needs more participants to start** — the plain card at 30% opacity: still clickable but de-emphasized. Tapping it explains why ("Uh oh, you need to invite N people…").

A card the learner has **saved a session of** wears the gold double-ring **played stamp** in its top-right corner, with "×N" when they have saved it more than once — beside a live state, never instead of it. It is the same stamp the map puts at a played activity's location ([world-map.instructions.md](world-map.instructions.md), "Played stamps").

## Mission header states on the course plan

Each Mission's header on the full course plan tells the learner at a glance whether it is done, next, or later ([client#8874](https://github.com/pangeachat/client/issues/8874) — before this, the only mark was the statement's text colour, which nobody could see). Three states:

- **Up next** — the shared resolver's anchor for this course. Its header carries an "Up next" label, and its statement and XP count take the `primary` accent; the label says the state in words, so it is never colour alone. Nothing wraps the section: a band or an outline around header and cards was tried and dropped, because a tint shows the carousel's surface-coloured scroll-arrow strip as a notch and any inset throws the section's margins off against its neighbours. At most one Mission per course wears it, and a complete Mission never does — once the whole course is complete there is no anchor, so no Mission carries the label ([client#8997](https://github.com/pangeachat/client/issues/8997)).
- **Complete** — XP at or past the threshold. The star before the count fills (it is outlined while in progress) and the header text drops to `onSurfaceVariant`, so finished work reads as done without disappearing: its activities stay in view and playable, since a learner can still raise its XP.
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

- A persisted per-Mission XP total (server-side rollup) once reading every session room and the local analytics database client-side becomes too costly at catalog scale.
- Teacher-set **hard** restrictions (an opt-in gate on top of the soft default), if classroom demand appears — deliberately not built today (see the org doc). Distinct from per-course activity pinning (above), which is built and restricts *which activities count*, not *when Missions are reachable*.
- Implement the joinable/open activity card design — [pangeachat/client#7669](https://github.com/pangeachat/client/issues/7669).
- Design hint indicating an activity needs more people to start — [pangeachat/client#6810](https://github.com/pangeachat/client/issues/6810).
