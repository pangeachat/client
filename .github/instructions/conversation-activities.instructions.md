---
applyTo: "lib/pangea/activity_planner/**,lib/pangea/activity_sessions/**,lib/pangea/activity_suggestions/**,lib/pangea/activity_summary/**"
---

# Activity System

Activities are how Pangea Chat turns passive chatting into deliberate language learning. Activities are designed according best practices in task-based language teaching and second language acquisition research, with a focus on maximizing engagement and learning outcomes while minimizing friction.

## Design Goals

1. **Conversation games**: We would like user's to think of and describe these experiences as 'games'. That is how we will know we have arrived. 
2. **Minimal front-loaded instruction**: Historically, conversation practice is proceeded by learning lists of vocab and grammar, which are quickly forgotten. Instead, we want to get users practicing real conversations as quickly as possible, with any necessary instruction or feedback integrated into the experience rather than front-loaded.
3. **AI-powered assistance**: The system should leverage AI to provide personalized assistance, feedback, and content generation to enhance the learning experience.
4. **Data-driven**: Every interaction should generate data that can be used to improve the system, understand user behavior, and demonstrate learning outcomes.

---

## Structured Activities 

### The User Experience



### Key Technical Design Decisions

- **Activities are Matrix rooms.** This means all existing chat infrastructure (message events, timelines, sync) works automatically. No separate activity backend needed.
- **Course context is inherited.** Activity rooms know which course (space) they belong to via parent room relationships. This lets summaries reference the course's learning goals.

### Activity Lifecycle States

1. User picks an activity from their course
2. User starts activity
3. User chooses role
4. User decides who to play with
- Wait for course participants with optional "Ping" to course
- "Play with Pangea Bot" option for solo practice
- "Invite friends" option to share an invite link or invite specific users
5. Activity in progress
6. Users mark activity as finished
7. Activity summary generated and posted in the activity room, visible to all participants
8. Users archive activity when done reviewing the summary (removes from active view but retains in history)
Optionally, users can review past activities in their activity history, which surfaces summaries and outcomes from previous sessions. We intend to implement an explicit practice flow here.

An activity is "started" when all role slots are filled. It's "finished" when all non-bot participants have marked themselves done or left. "Archived" means the user has dismissed it from their active view.

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
