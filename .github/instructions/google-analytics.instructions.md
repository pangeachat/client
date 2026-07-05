---
applyTo: "lib/pangea/common/utils/firebase_analytics.dart,lib/features/navigation/**,lib/features/notifications/notification_tap_utils.dart"
description: "Product analytics (GA4 via Firebase) relative to the workspace routing — token-derived screen names, history-step emission, attribution before the #, no raw URLs in reporting."
---

# Google Analytics & the Workspace URL

Product analytics is GA4 via `firebase_analytics`, wrapped in
[`firebase_analytics.dart`](../../lib/pangea/common/utils/firebase_analytics.dart)
and called from discrete product moments (signup, login, subscription,
tutorials, notification opens, toolbar actions). The bot-notification open
event and its metadata are a separate cross-repo contract —
[bot-notification-open-analytics.instructions.md](../../../.github/.github/instructions/bot-notification-open-analytics.instructions.md)
— carried in Matrix event content, not URLs, so routing changes never affect
it.

This doc owns how analytics relates to the workspace routing model
([routing.instructions.md](routing.instructions.md)), where the path is always
`/` and what is on screen rides in the token lists. Discrete product events
exist today; **screen tracking is the not-yet-built piece this doc specifies.**

GA is the **measurement layer, not the decision layer**: per-user re-engagement
and onboarding decisions read first-party signals (persisted Matrix opened
events, Synapse user activity, journey-checklist state), and a GA-sourced
signal may only ever *suppress* a bot send, never cause one — the architecture
and rationale live in the
[engagement-analytics contract](../../../.github/.github/instructions/bot-notification-open-analytics.instructions.md).
Event names, params, and screen names are still a cross-service contract: the
measurement mirror must stay joinable by name with those first-party facts.

## Screen tracking

- **A screen name is the focused panel's token with identity stripped — token
  syntax, never a parallel naming scheme.** The path is always `/`, so default
  page tracking is meaningless, and raw workspace URLs are high-cardinality and
  unstable across grammar migrations. The derivation keeps the token's type and
  its navigational param (a tab, a page, a push leaf) and drops identity fields
  (lemmas, room and activity ids); the panel registry declares which is which
  per type. Examples: `world` (no focused panel), `chats`, `room`,
  `course:more`, `coursepage:invite`, `settingspage:security/3pid`,
  `settingspage:subscription`, `analytics:vocab`, `practice:grammar`,
  `activity`, `session`. One derivation, reading the same token input as
  `sectionFor`, so analytics can never disagree with the chrome or drift into a
  second vocabulary.
- **Screen views are the funnel view of journey steps.** Questions like "has
  this learner visited the subscription page" are answered in reporting by
  screen views (`settingspage:subscription`, `practice:vocab`). The bot-facing
  journey-checklist state is written first-party at the same moment through the
  product-moment helper (see Event shape below), with the screen view as its
  measurement mirror — another reason the names must stay stable and at exactly
  this grain.
- **Identity params stay out of screen names and registered dimensions.**
  Lemmas, ids, and room names are unbounded-cardinality and can be personal; an
  id appears only as a row-level event param where a contract already
  establishes it (the bot-notification contract's cardinality rule applies).
  Navigational params — a tab, a settings page, a push leaf — are the
  low-cardinality part that stays in the screen name.
- **Emit on a change of screen name, deduped.** The tracker
  (`WorkspaceScreenTracker`, listening on the router) derives the name on every
  navigation and emits only when it differs from the last. This makes the
  "replaces are silent" intent fall out for free: a width-driven fold/unfold or
  a refocus does not change the tokens, so the derived name is unchanged and
  nothing fires — resizing a window never pollutes a funnel. A genuine screen
  change (open, push, close, pop) mints a new name and emits; a `launch`
  transition into the session does too, because arriving at the session screen
  is a real screen view even though it replaces the history entry.
- **Event vocabulary matches the token grammar**: `vocab` / `grammar`, never
  `morph`.

## Event shape

Per-interaction events follow one shape, so the measurement mirror stays
joinable with the first-party decision facts and serves onboarding-timeline
reporting:

- **The learner rides every event** as the GA4 user id (the pseudonymous Matrix
  id), so per-learner BigQuery queries — opens, sessions, journey progress —
  are possible.
- **Notification-tap events carry the notification type and intended action**
  per the
  [bot-notification contract](../../../.github/.github/instructions/bot-notification-open-analytics.instructions.md);
  only those events have them.
- **Room-scoped events may carry a room id** as a row-level param, never a
  registered dimension (the cardinality rule).
- **Timestamp and web/mobile platform come from GA4 automatically** (event
  timestamp; per-platform streams) — do not duplicate them as params.
- **One writer per product moment.** A moment that both advances the
  first-party journey checklist and emits a GA event goes through a single
  client helper that writes both together, so state and mirror can never
  drift — the analytics twin of the routing rule that only `WorkspaceNav`
  writes URLs.

## Attribution

The client is hash-routed (`app.pangea.chat/#/…` — see
[deep-linking.instructions.md](../../../.github/.github/instructions/deep-linking.instructions.md)).
Web attribution params (`utm_*`, `gclid`) belong in the **real query string,
before the `#`**, where GA's web layer reads them at page load; the router only
ever sees the fragment, so routing and its no-loose-params rule never touch
attribution. Link producers (campaigns, emails, the website) put attribution
before the `#`, never inside the fragment route. No in-app code consumes
`utm_*` today; if acquisition tracking ever needs it in-app, it enters through
the analytics layer, not the router.

## Migration guard

Any GA report or exploration keyed on raw fragment URLs breaks as the grammar
migrates (`?m=` to `?c=`, token spellings). Screen names above are the stable
reporting key; before the routing cutover, sweep for fragment-URL dependence in
pangea-bot's BigQuery queries first (they gate real notification sends), then
dashboards and explorations.

## Testing

The screen-name derivation is unit-tested beside the token parser's round-trip
tests: token lists in, stable names out, including folded and single-column
states.
