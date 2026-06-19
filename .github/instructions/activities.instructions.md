---
applyTo: "lib/features/activity_sessions/**,lib/features/quests/**,lib/routes/chat/activity_sessions/**,lib/routes/chat/chat_details/**"
description: "Client design for activities: thin cards, the start page's room-driven state, navigation, and the media carousel (video next)."
---

# Activity System

Conversation activities are structured, game-like conversations. What an activity *is* — its schema, goals, session lifecycle, and the Matrix-room contract behind it — is owned by the org-wide [activities doc](../../../.github/.github/instructions/activities.instructions.md); backend generation and the read endpoints by the [choreographer doc](../../../2-step-choreographer/.github/instructions/activities.instructions.md); and the video-first way activities get their media by [media-first generation](../../../.github/.github/instructions/media-first-activity-generation.instructions.md). This doc covers only how the **client** discovers, opens, runs, and shows an activity.

## Cards are thin; the plan is full

The cards a learner browses — in lists, on map pins, under a learning objective — are deliberately lightweight: a title, a level, a place, the searchable basics, and nothing more. The full activity, including its media, loads only when the learner opens it. So media is always a property of the *opened* activity, never of the card list, and a card can show at most one thumbnail — and only once the activity behind it has loaded. [`QuestActivityCard`](../../lib/features/quests/models/quest_activity_card.dart) is the thin card; [`ActivityPlanModel`](../../lib/features/activity_sessions/activity_plan_model.dart) is the full thing.

## A running activity is a chat room

When a learner starts an activity, it becomes a Matrix room. That is the central design choice: a live session reuses the whole chat stack — timeline, sync, membership, roles — instead of a parallel "sessions" system. The room *is* the session. The shapes of the room and its state events are the org doc's contract; the client only reads them.

Course context is borrowed, not owned. An activity belongs to learning objectives, not to a course, so the client works out which course (if any) an activity sits under at the moment it opens — from the room's place in the space hierarchy, or by matching when an activity is opened on its own. A session with no course behind it is perfectly valid.

## The start page mirrors the room

The activity's start page doesn't store its own state; it reads it from the room — whether a room exists yet, whether the learner is in it, whether they've taken a role, whether every role is filled. From those facts it moves through a short sequence (not started → picking a role → in with a role → session full) and shows the right thing at each step: the waiting room (ping the course, play with the bot, or invite a friend — pinging is limited to once a minute so it can't be spammed), the role picker, or the live activity.

When a session counts as "ended" is the org doc's call. The client's part is firing the summary once that happens, and keeping a short-lived local cache of the room's analytics so the page doesn't re-fetch on every visit.

## Two ways in

An activity opens one of two ways: as an overlay over the world map (when the learner is inside its course) or from its own shareable link (when they reach it directly). Both open the same activity surface — a side panel on desktop, a bottom sheet on mobile. A link can also ask to skip the lobby straight to role selection, or to reopen a specific in-progress session. The exact URL shapes are the cross-repo [deep-linking](../../../.github/.github/instructions/deep-linking.instructions.md) contract; this doc only relies on them.

## Media is a carousel

An activity's stimulus is a carousel of mixed media — images, audio, and video (uploaded or from YouTube) — in a set order; a single image is just a carousel of one. The kinds of block and the rules for resolving and rendering them are the org doc's. What the client owns is turning that list into something the learner can see.

Two things shape how the client renders it. First, uploaded media arrives as a reference, not an address, so the client resolves it to a real URL before showing anything — and **every path that prepares an activity for display must resolve, or the media falls back to a placeholder.** YouTube blocks are the exception: they already carry their link. Second, how much of the carousel a surface shows depends on the room it has — a focused surface (the plan page, the live session) presents the whole carousel; a compact surface (a card, a map pin) shows just the first block, standing in for the rest. When an activity has only one piece of media, there is nothing to page through: the carousel degrades to a single display with no navigation controls. [`ActivityMediaBlock`](../../lib/features/activity_sessions/activity_media_block.dart) is the media model.

On the web, media images are fetched in a way that needs the content CDN to allow cross-origin requests; that requirement lives in the org and devops docs, not here.

## Video: inline in some places, a thumbnail in others

Video is where the two surfaces differ most:

- **On a focused surface — the plan page, the live session — each block plays in place.** Images show, uploaded videos use the app's player, and YouTube always plays as an embed, never downloaded or re-hosted (YouTube's terms forbid it). The carousel stays calm: the learner swipes through blocks, a video plays only when they tap it, and nothing starts on its own.
- **On a compact surface — a card, a map pin — the first block stands in for the carousel, carrying a play badge when it's a video.** That is what makes a card carousel-aware: a video-first activity leads with its video, not an unrelated image. Tapping it doesn't play it there; it opens the activity with that video starting.

That tap is the *only* time a video starts on its own, and it starts **muted, with a tap to unmute**. Muting is what lets it start at all — browsers block sound the learner didn't ask for — and it keeps the feel consistent with tap-to-play everywhere else. The request to autoplay travels with the activity's link, so reopening or sharing that link replays the same thing, the same way "skip to role selection" and "reopen this session" do.

## Future Work
*Last updated: 2026-02-15*

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
