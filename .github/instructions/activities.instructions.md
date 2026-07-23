---
applyTo: "lib/features/activity_sessions/**,lib/features/quests/**,lib/routes/chat/activity_sessions/**,lib/routes/chat/chat_details/**"
description: "Client design for activities: thin cards, the start page's room-driven state, navigation, and the media carousel (video next)."
---

# Activity System

Conversation activities are structured, game-like conversations. What an activity _is_ — its schema, goals, session lifecycle, and the Matrix-room contract behind it — is owned by the org-wide [activities doc](../../../.github/.github/instructions/activities.instructions.md); backend generation and the read endpoints by the [choreographer doc](../../../2-step-choreographer/.github/instructions/activities.instructions.md). This doc covers only how the **client** discovers, opens, runs, and shows an activity.

## Cards are thin; the plan is full

The cards a learner browses — in lists, on map pins, under a learning objective — are deliberately lightweight: a title, a level, a place, the searchable basics, and nothing more. The full activity, including its media, loads only when the learner opens it. So media is always a property of the _opened_ activity, never of the card list, and a card can show at most one thumbnail — and only once the activity behind it has loaded. [`QuestActivityCard`](../../lib/features/quests/models/quest_activity_card.dart) is the thin card; [`ActivityPlanModel`](../../lib/features/activity_sessions/activity_plan_model.dart) is the full thing.

## A running activity is a chat room

When a learner starts an activity, it becomes a Matrix room. That is the central design choice: a live session reuses the whole chat stack — timeline, sync, membership, roles — instead of a parallel "sessions" system. The room _is_ the session. The shapes of the room and its state events are the org doc's contract; the client only reads them.

Course context is borrowed, not owned. An activity belongs to learning objectives, not to a course, so the client works out which course (if any) an activity sits under at the moment it opens — from the room's place in the space hierarchy, or by matching when an activity is opened on its own. A session with no course behind it is perfectly valid.

On the write side, starting a session shares it into **every joined course the activity is eligible for** — each course whose learning objectives intersect the activity's, at a matching target language — as an `m.space.child` of that course's space, so coursemates and teachers can discover and join it. Eligibility is that direct learning-objective intersection ([`ActivityCourseResolver`](../../lib/routes/world/activity_course_resolver.dart)), _not_ membership in a course's hand-listed activity set; it is the same rule whether the session is launched from the course page or from a bare map pin. The launched-from course is additionally recorded as the session's origin (`source_course_id`) — a single provenance field, while the `m.space.child` set is the full eligible fan-out. The fan-out is client-side and best-effort, so it only reaches courses **the launcher has joined**; surfacing a session to a course the launcher is not in is the map's read-side job (see [world-map.instructions.md](world-map.instructions.md)).

## The start page mirrors the room

The activity's start page doesn't store its own state; it reads it from the room — whether a room exists yet, whether the learner is in it, whether they've taken a role, whether every role is filled. From those facts it moves through a short sequence (not started → picking a role → in with a role → session full) and shows the right thing at each step: the waiting room (ping the course, play with the bot, or invite a friend — pinging is limited to once a minute so it can't be spammed), the role picker, or the live activity.

When a session counts as "ended" is the org doc's call. The client's part is firing the summary once that happens, and keeping a short-lived local cache of the room's analytics so the page doesn't re-fetch on every visit.

## Completion saves itself

Saving a completed session is automatic — the design (what saving means, when it happens, and how stars bank on it) is the org doc's ([Saving and stars](../../../.github/.github/instructions/activities.instructions.md#saving-and-stars)); what the client owns is where the save runs. [`ActivityAutoSaveService`](../../lib/features/activity_sessions/activity_auto_save_service.dart) watches activity-role state changes across **all** rooms, not just the open chat, so a session that completes while the learner is elsewhere — or that completed before this login — still saves on the next sync. The save is idempotent, so a second device observing the same completion is harmless. A room whose plan is still hydrating is retried once the plan lands; a room whose plan is gone entirely (the archived-view rung in [When the activity can't be fetched](#when-the-activity-cant-be-fetched)) cannot resolve a target language and is skipped.

The profile star counter ([`totalStarsEarned`](../../lib/routes/chat/choreographer/activity_orchestrator/orchestrator_client_extension.dart)) counts saved sessions only. In-session star displays and per-activity progress on cards stay live — only the profile total waits for the save.

## Downloading the transcript

The session's app bar carries a "More" (⋮) menu ([`ActivitySessionPopupMenu`](../../lib/routes/chat/activity_sessions/activity_session_popup_menu.dart)). A **live** session offers Invite, Leave, and Download; a **completed** session — finished for everyone (`isActivityFinished`) — keeps the menu but offers **Download only**, since Invite and Leave no longer apply once the session is over. The gate is the session ending for all, _not_ the learner's own role archiving (`hasArchivedActivity`): an observer who never took a role, or a learner who finished while others played on, is still looking at a session that has ended, and the archived-role state is both narrower and reached only after auto-save. Completing a session must not strip the menu: a learner returning to a finished session still needs to export it. (Regular, non-activity chats expose the same export from the chat-details button row, not this menu.)

Download exports the full message history — sender, timestamp, original and sent message, and use type — as TXT / CSV / XLSX ([`lib/features/download/`](../../lib/features/download/)). Two decisions govern who sees it and where:

- **Any room member can export.** The download only surfaces content the member can already read in the chat, so it grants no new visibility. Do not gate it behind power level. The one real cost is that it puts an off-platform copy of a whole room's messages — everyone's, in a group or multi-learner session — in one member's hands; for research-study or minor-heavy rooms that off-platform copy is a genuinely different exposure from in-app reading, and is the open question to revisit if the studies need tighter control.
- **Web and desktop only, for now.** The download is `kIsWeb`-gated because the native mobile write path (`download_file_util.dart`, storage-permission + Downloads dir) has never shipped and is unvalidated. Enabling mobile is deliberately deferred until that path is tested — until then a completed session on native shows no ⋮ menu at all (Download would be its only item).

## When the activity can't be fetched

Some session rooms reference an activity that no longer exists on the backend. The fallback ladder and the view-only contract are the org doc's ([Removed or unresolvable activities](../../../.github/.github/instructions/activities.instructions.md#editing-semantics)); what the client shows on each rung:

- **Legacy room with the plan embedded in state** — old rooms stored the whole plan in the `pangea.activity_plan` event, and [`ActivityPlanRepo`](../../lib/features/activity_sessions/activity_plan_repo.dart) falls back to it when the fetch confirms the activity is gone. The session page looks normal — hero media, role cards, goals with labels, description and vocab — but is **view-only**: no picking a role, no scoring, no suggestions. The session presents as ended without writing anything to the room. The summary section works: a cached summary shows, and a new one can still be generated.
- **No plan anywhere** — instead of an error, the page shows an **archived session**: room name as the title, participants with their roles and finished status, star counts without goal labels, the conversation timeline, and the cached summary if one exists. A banner explains the activity ran on an older version of activities and is no longer supported.
- **Transient fetch failure** (network, backend down) — a retryable error state, never the archived view or the "no longer supported" banner. Only a confirmed "this activity is gone" response walks down the ladder.

The page never gates its whole render on the plan fetch — the timeline, roles, and progress always display from room state.

## Two ways in

An activity opens one of two ways: as an overlay over the world map (when the learner is inside its course) or from its own shareable link (when they reach it directly). Both open the same activity surface — a side panel beside the map on a wide screen, a half-open bottom sheet on narrow with the camera settled on its map location (the Google Maps target UX), swipe-expandable to the full plan; see [routing.instructions.md](routing.instructions.md). A link can also ask to skip the lobby straight to role selection, or to reopen a specific in-progress session. The exact URL shapes are the cross-repo [deep-linking](../../../.github/.github/instructions/deep-linking.instructions.md) contract; this doc only relies on them.

## Media is a carousel

An activity's stimulus is a carousel of mixed media — images, audio, and video (uploaded or from YouTube) — in a set order; a single image is just a carousel of one. The kinds of block and the rules for resolving and rendering them are the org doc's. What the client owns is turning that list into something the learner can see.

Two things shape how the client renders it. First, uploaded media arrives as a reference, not an address, so the client resolves it to a real URL before showing anything — and **every path that prepares an activity for display must resolve, or the media falls back to a placeholder.** YouTube blocks are the exception: they already carry their link. Second, how much of the carousel a surface shows depends on the room it has — a focused surface (the plan page, the live session) presents the whole carousel; a compact surface (a card, a map pin) shows just the first block, standing in for the rest. When an activity has only one piece of media, there is nothing to page through: the carousel degrades to a single display with no navigation controls. [`ActivityMediaBlock`](../../lib/features/activity_sessions/activity_media_block.dart) is the media model.

On the web, media images are fetched in a way that needs the content CDN to allow cross-origin requests; that requirement lives in the org and devops docs, not here.

## Video: inline in some places, a thumbnail in others

Video is where the two surfaces differ most:

- **On a focused surface — the plan page, the live session — each block plays in place.** Images show, uploaded videos use the app's player, and YouTube always plays as an embed, never downloaded or re-hosted (YouTube's terms forbid it). The carousel stays calm: the learner swipes through blocks, a video plays only when they tap it, and nothing starts on its own. **Playing in place is web and desktop only.** On native mobile the focused surface is a scrolling bottom sheet, and a live player is a platform view (webview) that can't live inside a scrolling sheet — it escapes the sheet's bounds and its drag gestures force the embed into an inexitable fullscreen ([#7672](https://github.com/pangeachat/client/issues/7672)/[#7673](https://github.com/pangeachat/client/issues/7673)). So on iOS/Android a tapped video opens on its own full-screen player with an obvious close, instead of inline.
- **On a compact surface — a card, a map pin — the first block stands in for the carousel, carrying a small video tag (not a play badge) when it's a video.** That is what makes a card carousel-aware: a video-first activity leads with its video, not an unrelated image. The tag differentiates video without a play badge's false promise of play-in-place: tapping the card doesn't play the video there; it opens the activity, where the video starts. (A centered play badge on a card read as "play here" and did nothing on tap — see [pangeachat/client#7543](https://github.com/pangeachat/client/issues/7543).)

That tap is the _only_ time a video starts on its own, and it starts **muted, with a tap to unmute**. Muting is what lets it start at all — browsers block sound the learner didn't ask for — and it keeps the feel consistent with tap-to-play everywhere else. The request to autoplay travels with the activity's link, so reopening or sharing that link replays the same thing, the same way "skip to role selection" and "reopen this session" do.

---

Do not add ActivityVocabWidget to ActivityStatsMenu.

## Future Work

_Last updated: 2026-02-15_

**Lifecycle & Session Management**

- [pangeachat/client#5390](https://github.com/pangeachat/client/issues/5390) — Separate activities where user has a role from ones where they do not
- [pangeachat/client#4805](https://github.com/pangeachat/client/discussions/4805) — Open/Joined/Done Activities not sorted
- [pangeachat/client#4955](https://github.com/pangeachat/client/discussions/4955) — Highlight ongoing and open sessions
- [pangeachat/client#4666](https://github.com/pangeachat/client/discussions/4666) — Auto-save to completed activities
- [pangeachat/client#4667](https://github.com/pangeachat/client/discussions/4667) — Disallow kicking activity members with roles
- [pangeachat/client#5435](https://github.com/pangeachat/client/discussions/5435) — On activity completion, create set of multiple-choice checks
- [pangeachat/pangea-bot#1002](https://github.com/pangeachat/pangea-bot/issues/1002) — If goals seem complete, suggest they end the activity
- [pangeachat/pangea-bot#999](https://github.com/pangeachat/pangea-bot/issues/999) — If stale activity session in-waiting, offer to do it
- [pangeachat/pangea-bot#967](https://github.com/pangeachat/pangea-bot/issues/967) — Invite user to activity session

**Roles & Bot Behavior**

- [pangeachat/2-step-choreographer#1709](https://github.com/pangeachat/2-step-choreographer/issues/1709) — In Activity, if Bot's role shouldn't start activity, wait before posting message
- [pangeachat/2-step-choreographer#1639](https://github.com/pangeachat/2-step-choreographer/issues/1639) — Activity roles look strange in non-english

**Activity Summaries**

- [pangeachat/2-step-choreographer#1340](https://github.com/pangeachat/2-step-choreographer/issues/1340) — activity summary not in activity's language of instruction
- [pangeachat/2-step-choreographer#1695](https://github.com/pangeachat/2-step-choreographer/issues/1695) — Don't make punctuation corrections on voice message transcriptions
- [pangeachat/2-step-choreographer#1102](https://github.com/pangeachat/2-step-choreographer/issues/1102) — Duplicate superlatives

**Descriptions & Onboarding UX**

- [pangeachat/2-step-choreographer#1707](https://github.com/pangeachat/2-step-choreographer/issues/1707) — Simplify Activity Descriptions
- [pangeachat/2-step-choreographer#1708](https://github.com/pangeachat/2-step-choreographer/issues/1708) — Include translations for activity description examples
- [pangeachat/client#5609](https://github.com/pangeachat/client/issues/5609) — Copy/Paste single words or letters feature
- [pangeachat/client#5613](https://github.com/pangeachat/client/discussions/5613) — Shorten the learning curve time, especially for A1 users
- [pangeachat/client#3382](https://github.com/pangeachat/client/discussions/3382) — More interesting loading screen during activity generation?
- [pangeachat/client#4956](https://github.com/pangeachat/client/discussions/4956) — Add help-walkthrough for Course Page
- [pangeachat/client#4947](https://github.com/pangeachat/client/discussions/4947) — Hard to tell where Activity Ping is coming from

**Activity Content & Media**

- [pangeachat/2-step-choreographer#1106](https://github.com/pangeachat/2-step-choreographer/issues/1106) — Generate role images based on activity images
- [pangeachat/2-step-choreographer#1118](https://github.com/pangeachat/2-step-choreographer/issues/1118) — retry with feedback on image generation content violation
- [pangeachat/2-step-choreographer#1440](https://github.com/pangeachat/2-step-choreographer/issues/1440) — Endpoint: Add avatar image to scene
- [pangeachat/2-step-choreographer#1209](https://github.com/pangeachat/2-step-choreographer/issues/1209) — Prototype activity video search
- [pangeachat/2-step-choreographer#1103](https://github.com/pangeachat/2-step-choreographer/issues/1103) — Add morphs to activities
- [pangeachat/client#4650](https://github.com/pangeachat/client/discussions/4650) — Should generated images match art style associated with region language is associated with?
- [pangeachat/client#2837](https://github.com/pangeachat/client/discussions/2837) — Integrating YouTube videos
- [pangeachat/client#2773](https://github.com/pangeachat/client/discussions/2773) — Turn a link to interact-able activities
- [pangeachat/cms#128](https://github.com/pangeachat/cms/issues/128) — Course languages get mixed up when previously translated
- [pangeachat/cms#43](https://github.com/pangeachat/cms/issues/43) — Because course image is loaded from topic image, course image is not available until topics are fully loaded

**Planning, Courses & Discovery**

- [pangeachat/client#5196](https://github.com/pangeachat/client/issues/5196) — Don't see what you need? Course request button
- [pangeachat/client#4793](https://github.com/pangeachat/client/discussions/4793) — In-app request for course
- [pangeachat/client#2751](https://github.com/pangeachat/client/discussions/2751) — Mapping Learning Objectives with CEFR or ACTFL
- [pangeachat/client#2185](https://github.com/pangeachat/client/discussions/2185) — Limit activity planner mode to provided choices?
- [pangeachat/client#1658](https://github.com/pangeachat/client/discussions/1658) — Activity Planner Ideas

**New Activity Types & Game Ideas**

- [pangeachat/client#4841](https://github.com/pangeachat/client/discussions/4841) — Other Activity Game Ideas
- [pangeachat/client#3952](https://github.com/pangeachat/client/discussions/3952) — I Spy vocab game

**Teacher Experience**

- [pangeachat/client#1837](https://github.com/pangeachat/client/discussions/1837) — Teacher's feedback (will add more)
