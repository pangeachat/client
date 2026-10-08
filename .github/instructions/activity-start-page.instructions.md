---
applyTo: "lib/routes/chat/activity_sessions/**,lib/routes/world/**,lib/widgets/layouts/mobile_nav_widget.dart,lib/widgets/layouts/workspace_shell.dart"
description: "The activity start page's layout and interaction: the mobile grow-before-scroll sheet, the header + info row, the CTA row, the suggested-vocab word cards, and how the page owns its container over the nav rail and analytics bar."
---

# Activity Start Page

The start page is the panel a learner opens by tapping an activity — from a map pin or from a course plan. Its lifecycle (which step it shows, driven by the room) is [activities.instructions.md](activities.instructions.md#the-start-page-mirrors-the-room); this doc owns only its **layout and gestures**: how it fills its container, what the top of it shows, and how the buttons lay out.

One widget renders in two hosts, and the platform difference lives in the host, not the page: on narrow screens it is the swipe-expandable sheet inside the mobile nav container ([`MobileNavWidget`](../../lib/widgets/layouts/mobile_nav_widget.dart)); on wide screens it is a floating card beside the map ([`WorkspaceLeftPanel`](../../lib/routes/world/left_panel/workspace_left_panel.dart) → [`PanelCard`](../../lib/routes/world/panel_card.dart)). Both mount [`ActivitySessionStartPage`](../../lib/routes/chat/activity_sessions/activity_session_start_page.dart) via [`LeftPanelActivityDetailsSubpage`](../../lib/routes/world/activity_detail_panel.dart). Prominence comes entirely from the container behavior below — the page owns its rounded container and, at full size, reaches over the chrome around it. It gets **no** added scrim, extra shadow, border, or accent.

## The sheet grows before it scrolls

On mobile the sheet has **two visible stops**: a **minimized** rest and **full**. The mid-level was dropped — its only extra over minimized was a sliver of the media, which isn't worth a stop. Minimized shows just the header, info row, and CTA (no media, description, or roles); full is the whole plan. Dragging up (or tapping the minimized sheet's dead space) opens full; dragging down past minimized dismisses the sheet (the Google-Maps pull-away). Under the hood this reuses the cavity's `half` stop, sized to the minimized height via `preferredCavityHeightPx`, so there is no taller stop between it and `full` ([`NavCavityHeight`](../../lib/widgets/layouts/mobile_nav_widget.dart)); `collapsed` remains the drag-down dismissal. Heights are approximate, so a sliver may peek — acceptable, and preferable to snapping to a content boundary.

The sheet **never remembers a manual resize**: it always re-opens at the minimized rest, so a maximized activity that is closed and reopened comes back minimized (`rememberHeight` is off for the activity cavity in [`workspace_shell.dart`](../../lib/widgets/layouts/workspace_shell.dart)).

The reason this needs **no** scroll-vs-grow coordination: the minimized view has no scrollable content at all. A `LayoutBuilder` in the start page drops the media/description/roles below a height threshold (`kActivityCompactMaxHeight`), exactly as the course card's compact peek does ([`_kCompactCardMaxHeight`](../../lib/routes/chat/chat_details/space_details_content.dart)) — so at minimized an upward drag simply grows the sheet (nothing competes for the gesture), and the content mounts and scrolls once the sheet is full. Tap-to-expand rides the same `tapBodyExpands` path the course peek uses.

## Top row and info row

The top of the page is two rows, present at every size (they, with the CTA, are what the minimized stop is sized around):

- **Top row** — the activity **title**, the **focus** button, and a **close (X)** in the top-right. Focus zooms and pans the map all the way to this activity's pin — it already exists ([`activity_sessions_start_view.dart`](../../lib/routes/chat/activity_sessions/activity_sessions_start_view.dart) → [`MapCameraFocusRequests`](../../lib/routes/world/map_context.dart)); only its icon changed. The X dismisses the page (see [Owning the container](#owning-the-container-nav-rail-and-analytics-bar)).
- **Info row** — creator **avatar** and **name**, the activity **L2**, **level**, **participant count**, and the **rating**. The creator is the activity's **owner** (`res.plan.user_id`), resolved for display from that owner's Matrix profile, so a teacher controls their own credit by editing their profile and we store no second name. No usable profile — no account behind the MXID, or no display name on it — falls back to the stored MXID with a placeholder contact icon. **The PangeaChat avatar and name are reserved for `@system`-owned rows**, which are most of the catalog: crediting a person's hand-built work to Pangea is the failure this ordering prevents, so an ugly credit is preferred to a wrong one. The rating reuses [`ActivityRatingMeter`](../../lib/routes/chat/activity_sessions/activity_rating_meter.dart) — the NEW pill / tinted meter — and this stays the only surface that shows it (per [activities.instructions.md](activities.instructions.md#rating-an-activity)). This row is new: those fields exist on the model but were never gathered into a header, so a map explorer sees the essentials without expanding the sheet. The L2 chip doubles as the control for switching to that language when it is not what the learner is learning — [Switching from context](profile.instructions.md#switching-from-context) owns that behavior.

Below the info row the middle content (media carousel, description, suggested vocab, role cards) is unchanged, as is the role picker.

**Suggested vocab.** Tapping a word opens its word card over the page. While a card is open, tapping another word switches to that word's card in one tap, tapping the open word closes it, and a tap anywhere else only closes the card. Only the vocab words stay reachable behind an open card, so a dismissing tap can never land on the X, a role card or a CTA. The same [`ActivityVocabWidget`](../../lib/routes/chat/activity_sessions/activity_vocab_widget.dart) renders the vocab in the in-chat activity summary, which behaves the same way.

## The CTA row

The start page's main job is to put the learner in a conversation with as few choices as possible ([client#9333](https://github.com/pangeachat/client/issues/9333)). What it offers depends on the activity's state:

- **An ongoing session the learner is in** — **Continue** leads, and nothing else to start or join appears.
- **Open sessions to join** — the page opens straight on the **join list**, whether there is one open session or many, so a waiting classmate is never passed over for the bot. Sessions are sorted by when their members were last online, each labelled the way a profile is ("Currently active" / "Last active: 3:42 PM"), and each shows its open role, with a check when the learner has already completed that role. A quieter **Start my own** closes the list (hidden when the activity is locked). If every open session fills while the learner looks, the page falls back to the start choice.
- **A 2-player activity with no open sessions** — **Play with others** and **Play with Pangea Bot**, side by side with equal weight: tall tiles on wide screens, chips on mobile. Play with others goes to the role picker and then the waiting room; Play with Pangea Bot goes to the role picker and the bot joins as soon as the session exists.
- **A 3+ player activity with no open sessions** — a single **Start**, which leads to the role picker and the waiting room.
- **A locked activity** ([Mission locks](quests.instructions.md#mission-locks)) — "Finish earlier missions to unlock" and an **Unlock in {course}** button for each course that locks it, opening that course on its course plan. Open sessions on it can still be joined.

The buttons wait until the activity's lock is known, showing a loading bar rather than flashing a Start that then disappears.

A **Completed** button or chip appears only when the viewer has completed sessions to review — their own, or (for a course admin) everyone's with their own listed first — and opens the completed-sessions subpage. The selection logic is [`_NotStartedSessionCTAButtons`](../../lib/routes/chat/activity_sessions/activity_session_button_widget.dart) and the state machine is in [`activity_session_start_page.dart`](../../lib/routes/chat/activity_sessions/activity_session_start_page.dart).

**On mobile** the footer is a single horizontally scrolling row, Google-Maps style, with **share** and **flag** always appended last. The leading choice stretches to fill the free width when the chips fit, and the row scrolls only when they overflow. On the join list the minimized sheet can't show the list itself, so it offers **Join open session (N)**, which opens the sheet full, and **Start my own**. Every following chip — including share and flag — uses the light filled-container style, not a bare outline.

When a session still needs more participants, the blocking notice keeps **Invite** at every size but drops **pick a different activity** at the minimized rest — it only navigates away and wouldn't fit the short sheet — restoring it once the sheet is maximized (and always on web).

**On web** the CTA section is a vertical list with the same hierarchy: the leading choice filled in `primary`, every following action a fully filled but **quieter** tonal (`secondaryContainer`) button — under the fidelity scheme `primaryContainer` is the vivid brand fill, a near twin of `primary`, so it no longer reads as the lighter step. There is no horizontal CTA row on web.

### The waiting room

While a session waits for its seats to fill, a status line leads: **"Waiting m:ss · N online in {course}"**. The timer counts from when the session was created, so it survives leaving and coming back. "Online" uses the same rule as the green presence dot on an avatar, and the course is the one the session was started from (see [activities.instructions.md](activities.instructions.md#the-start-page-mirrors-the-room)). Below it, bringing people in leads: **Invite friends** and **Ping course participants** in the primary fill, then **Play with Pangea Bot** in the quieter style at the bottom. The bot button also re-invites the bot if it failed to join.

**Share** and **flag** do not sit in the web CTA list. **Share** is an app-bar action to the left of focus. **Flag** sits in the top-right of the text-content (description) section under the hero — so it rides the main step, not the join/completed sub-pages, where there is no description to anchor it. On mobile both stay as chips appended to the bottom CTA row.

While a confirmed session waits to fill (chat not started), a **"…"** menu takes the app-bar share slot on web — and is net-new on mobile, which has no app-bar share. It offers exactly what the session's chat-list row offers, built from the same list ([routing.instructions.md](routing.instructions.md) → A chat's header actions): go to course, notifications, **Leave**, and **Delete** for the room's admin. It carries none of the chat header's extras: invite is already a button in the waiting room, and there is no chat yet to search. It displaces share here so inviting people isn't confused with sharing the link.


## Owning the container: nav rail and analytics bar

The "nav rail" is the four icons that switch page/scope — the bottom row of the mobile nav container, and its wide-screen counterpart. Normally surfaces open in the container *above* those icons, so a learner can keep navigating. The activity start page instead **takes over the container**: while it is open the four nav items are gone, and the always-present **X** on the page is the way back to them. This replaces today's behavior, where the page opened above a still-visible rail that no longer controlled anything.

At the **full** stop only, the mobile sheet covers the top **analytics bar** ([`WorldAnalyticsBar`](../../lib/routes/world/world_analytics_bar.dart)); at minimized it stays visible. Two pieces make it "cover" rather than just "hide": the sheet's full-height bound reserves neither the analytics-bar band nor the rail's (the plan hides the rail), so it grows up into that space; and the bar fades out — kept mounted so it doesn't re-fetch — while the sheet is full. The signal is the nav cavity's `onCavityFullChanged`, published for the activity only through [`ActivitySheetFull`](../../lib/routes/world/map_context.dart) and read by the shell ([`workspace_shell.dart`](../../lib/widgets/layouts/workspace_shell.dart)). This is mobile-only: on the wide web panel the analytics cluster ([`WorldUserCluster`](../../lib/routes/world/world_user_cluster.dart)) stays beside the fixed panel, which has no maximize.

Even at full the page stays **inset with rounded corners over the map** — it is overlaid on the map, never true edge-to-edge fullscreen, on either platform. This is what keeps it feeling like a map panel rather than the chat view (which does take the whole screen). Reaching a genuine subpage from here — opening a chat — is the one case that leaves this panel model for the full-screen chat surface with its own back control.
