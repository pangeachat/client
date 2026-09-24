---
applyTo: "lib/features/activity_sessions/**,lib/features/quests/**,lib/routes/analytics/activities/**,lib/routes/chat/activity_sessions/**,lib/routes/chat/chat_details/**"
description: "Client design for activities: thin cards, the start page's room-driven state, navigation, and the media carousel (video next)."
---

# Activity System

Conversation activities are structured, game-like conversations. What an activity _is_ — its schema, goals, session lifecycle, and the Matrix-room contract behind it — is owned by the org-wide [activities doc](../../../.github/.github/instructions/activities.instructions.md); backend generation and the read endpoints by the [choreographer doc](../../../2-step-choreographer/.github/instructions/activities.instructions.md). This doc covers only how the **client** discovers, opens, runs, and shows an activity.

## Cards are thin; the plan is full

The cards a learner browses — in lists, on map pins, under a learning objective — are deliberately lightweight: a title, a level, a place, the searchable basics, and nothing more. The full activity, including its media, loads only when the learner opens it. So media is always a property of the _opened_ activity, never of the card list, and a card can show at most one thumbnail — and only once the activity behind it has loaded. [`QuestActivityCard`](../../lib/features/quests/models/quest_activity_card.dart) is the thin card; [`ActivityPlanModel`](../../lib/features/activity_sessions/activity_plan_model.dart) is the full thing.

## A running activity is a chat room

When a learner starts an activity, it becomes a Matrix room. That is the central design choice: a live session reuses the whole chat stack — timeline, sync, membership, roles — instead of a parallel "sessions" system. The room _is_ the session. The shapes of the room and its state events are the org doc's contract; the client only reads them.

Course context is borrowed, not owned. An activity belongs to learning objectives, not to a course, so the client works out which course (if any) an activity sits under at the moment it opens — from the room's place in the space hierarchy, or by matching when an activity is opened on its own. A session with no course behind it is perfectly valid.

On the write side, starting a session shares it into **every joined course the activity is eligible for** — each course whose learning objectives intersect the activity's, at a matching target language — as an `m.space.child` of that course's space, so coursemates and teachers can discover and join it. Eligibility is that direct learning-objective intersection ([`ActivityCourseResolver`](../../lib/routes/world/activity_course_resolver.dart)), _not_ membership in a course's hand-listed activity set; it is the same rule whether the session is launched from the course page or from a bare map pin. The launched-from course is additionally recorded as the session's origin (`source_course_id`) — a single provenance field, while the `m.space.child` set is the full eligible fan-out. The fan-out is client-side and best-effort, so it only reaches courses **the launcher has joined** — and that listing is also what a course shows: inside a course, only the sessions it lists are offered, so a session never surfaces in a course the launcher was not in ([#9026](https://github.com/pangeachat/client/issues/9026)). Any wider reach — sessions in courses the learner has not joined at all — is the world map's read-side job, and deferred ([world-map.instructions.md](world-map.instructions.md), Discovering joinable sessions).

## The start page mirrors the room

The activity's start page doesn't store its own state; it reads it from the room — whether a room exists yet, whether the learner is in it, whether they've taken a role, whether every role is filled. From those facts it moves through a short sequence (not started → picking a role → in with a role → session full) and shows the right thing at each step: the waiting room (ping the course, play with the bot, or invite a friend — pinging is limited to once a minute so it can't be spammed), the role picker, or the live activity.

When a session counts as "ended" is the org doc's call. The client's part is firing the summary once that happens, and keeping a short-lived local cache of the room's analytics so the page doesn't re-fetch on every visit.

The page's **layout and gestures** — the mobile grow-before-scroll sheet, the header and info row, the CTA row, and how it owns its container over the nav rail and analytics bar — are their own concern: [activity-start-page.instructions.md](activity-start-page.instructions.md).

## The goal header

A running activity carries its progress in a **goal header** pinned to the top of the conversation — a horizontal row of stars, one per goal, with the active goal named beneath them. It stays visible and sticky as the learner scrolls the timeline, and it is styled to read as a button (rounded corners, a drop shadow that lifts it off the conversation, a subtle hover state) because it is one: tapping it opens the full goal list. [`ActivityStatsMenu`](../../lib/routes/chat/activity_sessions/activity_stats_menu.dart) hosts it in the live session; the collapsed row is [`ActivityDropdownHeader`](../../lib/routes/chat/activity_sessions/activity_dropdown_header.dart) and the dropped-down panel is [`ActivityDropdownContent`](../../lib/routes/chat/activity_sessions/activity_dropdown_content.dart).

The header floats over the conversation, so the height it takes is chat the learner cannot read. A narrow window therefore uses smaller values for the header's own padding — the card's outer margin, and the band above and below the star row — while the stars and the goal label keep their size ([#9147](https://github.com/pangeachat/client/issues/9147)). Both faces use the same values, so the top of the header does not move when it opens. The lower limit is the toggle row's tap target, which stays at least 48px tall. The metrics are defined in one place, [`GoalHeaderConstants`](../../lib/routes/chat/activity_sessions/goal_header_constants.dart).

Stars fill in the goals' fixed order and never reshuffle — the goal a learner sees first stays first from start to finish. The **active goal** is the first one still unfinished: its star has a highlighted fill around it, and its description is the label under the row. Completing a goal fills its star wherever it sits, active or not; only when the _active_ goal's star fills does the next unfinished goal become active. So with three goals and the first active, finishing the second fills the second star while the first stays active; finishing the first then fills its star and hands active status to the third. Whenever any star is earned it flies up from the conversation and lands in its slot in the header, filling it in ([`GoalStarAnimation`](../../lib/routes/chat/choreographer/activity_orchestrator/goal_star_animation.dart), one star per goal via [`GoalStatusWidget`](../../lib/routes/chat/choreographer/activity_orchestrator/goal_status_widget.dart)).

Tapping the header drops it down. The stars shift from a horizontal row into a vertical column, and **each** goal — not just the active one — gets its full description beside its star. Tapping again collapses it. The end-activity actions live in this dropped-down view and are always reachable there: **"I'm done!"** ends the session for the tapping learner, and a learner may end early — the button is live before every star is filled and turns gold once they have completed all their own goals. **"End for all"** appears for admins (outside two-person bot sessions) and ends it for everyone. A learner who marked themselves done but changed their mind gets **"Wait, I'm not done!"** to return to the activity. Which buttons show is the `_showEndForMe` / `_showEndForAll` / `_showWaitNotDone` logic in [`ActivityStatsMenu`](../../lib/routes/chat/activity_sessions/activity_stats_menu.dart).

When a learner has earned every one of their stars, the whole header turns gold — background, border, and button — and in the collapsed state the active-goal label is replaced by a gold **"I'm done!"** button. Tapping that button ends the activity and shows the summary; tapping anywhere else on the header still drops it down to the full gold list, where "I'm done!" stays gold and clickable and "End for all" is there for admins.

The header's left slot, opposite the chevron, carries the session's language chip when that language can be switched to (it is not the user's L2 already, and it doesn't match the user's L1) — the one offer to switch that a running session has, since it has no Start or Join button to attach one to. The behavior is [Switching from context](profile.instructions.md#switching-from-context).

A header with no goals to show falls back to a plain **"Activity actions"** title in the same spot — no stars, but it still opens to the same end-activity buttons. This covers the admin or teacher who joins a session without taking a role (no goals of their own, but they still need "End for all") and any case where a role's goals can't be resolved — a legacy plan, or a failure loading or generating them — so a learner is never stranded without a way to end the activity.

Once the summary lands the header goes away and the summary carries the goals — under the participant picker, not above it. The stars there follow the pick: selecting a coursemate swaps their feedback card *and* their goal list, so the two always describe the same person. With no pick the viewer sees their own goals, and an observer who never took a role sees the first participant's ([#8672](https://github.com/pangeachat/client/issues/8672)).

### Reporting a wrong star (staging only)

On a staging build the team can report a star the orchestrator got wrong, so their complaints become data for improving it ([#9044](https://github.com/pangeachat/client/issues/9044)). **Tapping a star in the dropped-down goal list of a live session** opens the prompt: a filled star asks why it should not have been given, an empty one asks why it should have been and makes the reporter name one of their own messages in the session as the evidence. The comment is required either way — it is the whole diagnostic value of the report, and the server rejects a blank one — so submission stays blocked until one is typed, and for an empty star until a message is picked. The read-only goal lists — the start page's and the summary's — stay inert: the start page has no session to report against, and on the summary the list follows the participant picker, so a star there is as likely to be somebody else's as the reporter's.

**Only the stars in the dropped-down list report; the collapsed header's do not.** The collapsed row's one job is to open that list and its stars sit in the middle of it, so a report sharing that target would take taps away from opening the header — and the collapsed row carries no goal descriptions, which would mean reporting a star the reporter cannot read. Within the list each star is the tap target rather than its whole row, because the list's top row is what collapses it again.

**Nothing about the star changes.** The report is recorded against the orchestrator turn that awarded the goal, or failed to; it does not re-run the orchestrator, does not give or take a star, and does not alter the turn it concerns. The header is therefore left exactly as it was on success, and the prompt never implies the star will move. Every rejection is shown to the reporter rather than swallowed — a mis-aimed report, a legacy star with no turn to attach to, a retryable failure — because this is the team's own instrument and a silent failure is a complaint that was never recorded. The endpoint and its contract are the choreographer's: [conversation-orchestrator.instructions.md](../../../.github/.github/instructions/conversation-orchestrator.instructions.md).

## Completion saves itself

Saving a completed session is automatic — the design (what saving means, when it happens, and how stars bank on it) is the org doc's ([Saving and stars](../../../.github/.github/instructions/activities.instructions.md#saving-and-stars)); what the client owns is where the save runs. [`ActivityAutoSaveService`](../../lib/features/activity_sessions/activity_auto_save_service.dart) watches activity-role state changes across **all** rooms, not just the open chat, so a session that completes while the learner is elsewhere — or that completed before this login — still saves on the next sync. The save is idempotent, so a second device observing the same completion is harmless. A room whose plan is still hydrating is retried once the plan lands; a room whose plan is gone entirely (the archived-view rung in [When the activity can't be fetched](#when-the-activity-cant-be-fetched)) cannot resolve a target language and is skipped.

### Role state stays in step with the server

Every role lives in one shared role event (`pangea.activity_roles`), and two people writing to a room at the same moment can fork its history. When that happens, a sync can hand the client an older copy of the role event, and the Matrix SDK applies it over the newer one it already holds: a finished role reads as unfinished, the chat drops back to "Waiting to fill 1 role", and the save above skips the session ([#9229](https://github.com/pangeachat/client/issues/9229)). [`ActivityRolesStateRepair`](../../lib/features/activity_sessions/activity_roles_state_repair.dart) watches for the role event arriving that way and, when the room's copy differs from the server's current one, re-applies the server's copy through the SDK's own sync path. It only ever moves the client toward the server's state, never away from it, and each repair is reported to Sentry so we can see how often it happens.

The profile star counter ([`totalStarsEarned`](../../lib/routes/chat/choreographer/activity_orchestrator/orchestrator_client_extension.dart)) counts saved sessions only. In-session star displays and per-activity progress on cards stay live — only the profile total waits for the save.

## The Stars list

A saved session's row ([`AnalyticsActivityItem`](../../lib/routes/analytics/activities/activity_archive.dart)) is the learner's record of that session: the activity's title (the room's name once the plan is gone), their stars, their level, the XP they earned, and how many different vocabulary and grammar items they used. Every number comes from the summary saved with the session, so the row and the end-of-activity card can never disagree. Tapping a row opens the session.

The stats sit under the stars as one compact line — XP first, in the gold that marks XP everywhere else, then a vocabulary count and a grammar count behind the same two icons the analytics bar uses for words and grammar. The counts are of distinct items used in that session, not of items new to the learner: the saved summary does not record which were new, and the row never shows a number the summary cannot back. A count of zero shows as zero rather than dropping the stat, so the rows stay aligned down the list.

A session with no saved summary — an older one, or one whose generation failed — keeps its title and stars and shows nothing else: no level, no stats, and no gap where they would be. A summary is saved per display language, so a learner who has since changed their first language sees that same reduced row.

The open row carries the selected fill, and XP gives up the gold there so it stays readable against it.

## Rating an activity

Once a learner's own role is finished ("I'm done!", or an admin's "End for all"), a rating card pins to the bottom of the chat, above the finished-status bar: thumbs up/down, an optional comment, submit, and a dismiss X ([`ActivityRatingCard`](../../lib/routes/chat/activity_sessions/activity_rating_card.dart)). The "must have played" gate is client-trusted for v1 — a finished role is the evidence of play. Three rules govern when it shows ([#7194](https://github.com/pangeachat/client/issues/7194)):

- **A submitted rating is final for that version.** The device remembers the (activity, pinned version) it rated ([`ActivityRatingStore`](../../lib/features/activity_sessions/activity_rating_store.dart)) and the card never reappears for it. Dismissing with the X hides it for the current view only — reopening the finished, unrated session brings it back.
- **A newer version re-prompts.** The server keeps ONE opinion per (user, activity) and upserts, so re-rating a changed activity overwrites the learner's previous opinion — the aggregate reflects each rater's latest take, not per-version scores. The session's pinned `version_id` travels with the rating as analytics metadata only.
- **Failures degrade softly.** A comment rejected by post-time moderation (422) keeps the card open to reword or submit rating-only — the rating was not recorded. An owner rating their own activity (403) hides the card quietly and doesn't re-prompt.

The aggregate — an up-fraction and rater count served with the single-activity fetch — renders in the start page's top-right app-bar corner ([`ActivityRatingMeter`](../../lib/routes/chat/activity_sessions/activity_rating_meter.dart)): a **NEW** pill while the activity has fewer than the rating threshold (`kNewRatingThreshold`, currently 1 — i.e. unrated), then a small meter tinted from light red (all down) to light purple (all up). This header slot is the **only** surface that shows the badge or meter — map pins, large cards, and activity cards deliberately don't (the thin-card fields exist on `QuestActivityCard`, but the rating enters the map only as a score term — [world-map.instructions.md](world-map.instructions.md), Priority matrix).

## Downloading the transcript

The session's app bar carries the same **More** menu as any other chat ([routing.instructions.md](routing.instructions.md) → A chat's header actions): everything the session's chat-list row offers — go to course, notifications, end activity, leave, delete — plus **Invite** and **Download**, which exports the transcript. **Invite** is the one item the completion gate itself removes — a session that has ended, meaning finished for everyone (`isActivityFinished`), cannot be joined, though a learner coming back to it still needs to export it. That gate is the session ending for all, not the learner's own role archiving (`hasArchivedActivity`), which is narrower and reached only after auto-save — an observer who never took a role is still looking at a session that has ended. What else the menu shows tracks the learner's own role rather than the session's completion: End activity is offered only while they hold a role they have not finished, and Leave only until they have taken a role in a session that has started. (Regular, non-activity chats export from the chat-details button row instead.)

Download exports the full message history — sender, timestamp, original and sent message, and use type — as TXT / CSV / XLSX ([`lib/features/download/`](../../lib/features/download/)). Two decisions govern who sees it and where:

- **Any room member can export.** The download only surfaces content the member can already read in the chat, so it grants no new visibility. Do not gate it behind power level. The one real cost is that it puts an off-platform copy of a whole room's messages — everyone's, in a group or multi-learner session — in one member's hands; for research-study or minor-heavy rooms that off-platform copy is a genuinely different exposure from in-app reading, and is the open question to revisit if the studies need tighter control.
- **Web and desktop only, for now.** The download is `kIsWeb`-gated because the native mobile write path (`download_file_util.dart`, storage-permission + Downloads dir) has never shipped and is unvalidated. Enabling mobile is deliberately deferred until that path is tested — until then a completed session on native shows no ⋮ menu at all (Download would be its only item).

## Plans arrive a screenful at a time

A course screen shows one activity per session room, and each needs its plan. Fetching them one at a time made a single screen cost dozens of round trips, so [`ActivityPlanRepo`](../../lib/features/activity_sessions/activity_plan_repo.dart) collects the keys a frame asks for and reads them in one request. Cards still appear together; what changed is how many times the device asks.

Collecting them depends on waiting: surfaces request a plan per card as they build, so dispatching on the first request would send it before the second arrived and batch nothing. The repo therefore dispatches after the frame finishes asking — soon enough that nothing is perceptibly delayed, late enough that a screen travels as one request.

Three rules decide what can share a request, and each exists because ignoring it would quietly change what a caller asked for:

- **One display language per request.** The read applies a single language to everything in it, so a key wanting a different one starts a new request rather than being reordered into an existing one — hydration follows the order surfaces asked, and a learner watching a screen fill in should not see it rearranged to suit the transport.
- **A refresh travels alone.** Re-reading past the cache is the whole point of a refresh, and a shared request cannot ask for that on behalf of one activity and not the others.
- **Activities already known to be gone never travel.** The backend's "this is gone" verdict outlives the app session, so a known-dead activity is dropped before the request rather than re-asked — re-asking is a loop this system has already been through once.

Batching changes the number of requests, never their standing: each activity in a request costs the learner's allowance exactly what it would have cost alone, and one activity's failure never decides another's. What the backend guarantees in return is in the [org activities doc](../../../.github/.github/instructions/activities.instructions.md).

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

**Captions show in the activity's language.** YouTube shows captions by default, and we let it: the embed can't see a learner's own YouTube caption setting, so there is no "off" to respect. What we set is the track: **the activity's target language**, so a Spanish activity captions in Spanish. Same-language subtitles support listening practice, and tying the track to the activity rather than to the app's UI language keeps it right for a learner working across several languages. When the activity's language is unknown we name none and let YouTube choose. A learner who wants another language picks it from YouTube's own caption menu, which is why [#7693](https://github.com/pangeachat/client/issues/7693) needed no toggle of ours.

Two limits come from YouTube. It only picks a track the video has, so a video with no caption track in the activity's language shows its default track instead. And turning captions off and on with the CC button brings back the video's default track, which YouTube then remembers for later videos. On iOS and Android we clear that remembered language each time a video opens, so every video starts in the activity's language again. On web YouTube keeps it inside its own frame, which the app can't reach, so we don't clear it there ([#8828](https://github.com/pangeachat/client/issues/8828)).

**The embed takes the mouse only once the learner clicks it.** On the web a playing embed is a separate page inside ours, and the browser hands it every mouse event over its area. Left alone, a wheel over the video scrolls nothing, and a card floating over the video cannot be clicked ([#9063](https://github.com/pangeachat/client/issues/9063)). So the video area behaves like the rest of the page until the learner clicks it. That click plays or pauses, as a click on any video does, and from then on YouTube's own controls answer the mouse. Moving the pointer off the video gives the area back to the page. The cost is that YouTube's hover bar needs that one click first. A touch screen has no pointer to move away, so after the first tap the embed keeps touches.

**The keyboard plays video without leaving the app.** The thumbnail is a button named "Play video", and the playing video is one Tab stop named for what it is. Each has the usual [focus ring](accessibility.instructions.md#focus-rings). With focus on the player, Space, Enter or K plays and pauses, M mutes and unmutes, and C turns captions on and off. K, M and C are YouTube's own keys, so a learner who knows them there already knows them here. M is also the keyboard's "tap to unmute" for a video that started muted from a link. Focus stays on our control and never moves into the YouTube frame. The way back out of that frame is about fifty Tab presses through YouTube's related-video links, it ends at the top of the page, and the app cannot hear Escape from inside another site's frame. A screen reader can still walk into the frame and use YouTube's buttons, which sit behind its "Show player controls" button while its bar is hidden. We do not depend on that. Where the browser blocks a video from starting with sound, as Safari's engine does, the player opens paused and the first press of Space, or the first click, starts it. Seeking and volume level have no key. The same keys work on the app's player for uploaded videos.

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
