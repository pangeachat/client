---
applyTo: "lib/routes/chat/activity_sessions/**,lib/routes/world/**,lib/widgets/layouts/mobile_nav_widget.dart,lib/widgets/layouts/workspace_shell.dart"
description: "The activity start page's layout and interaction: the mobile grow-before-scroll sheet, the header + info row, the CTA row, and how the page owns its container over the nav rail and analytics bar."
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

Below the info row the middle content (media carousel, description, suggested vocab, role cards) is unchanged, as are the later steps of the flow (the role picker and the waiting-room actions — invite / ping / play with the bot).

## The CTA row

**On mobile** the footer is a single horizontally scrolling row, Google-Maps style. Exactly one **primary** (filled) CTA leads, followed by the other available actions, with **share** and **flag** always appended last. The primary is chosen by:

- an **ongoing** session the learner is in wins outright — it becomes the primary, and no Start or Join chip appears;
- otherwise, if any **joinable** open session exists, **Join open session** is primary (Start becomes a following chip);
- otherwise **Start** is primary.

When the chips fit the row, the primary CTA **stretches to fill** the free width; the row falls back to horizontal scrolling only when they overflow.

A **Completed** chip appears only when the viewer has completed sessions to review — their own, or (for a course admin) everyone's with their own listed first — and opens the completed-sessions subpage. Every chip already has a destination — the selection logic is [`_NotStartedSessionCTAButtons`](../../lib/routes/chat/activity_sessions/activity_session_button_widget.dart) and the state machine in [`activity_session_start_page.dart`](../../lib/routes/chat/activity_sessions/activity_session_start_page.dart); this change is about layout, not about adding destinations. Every non-primary chip — including share and flag — uses the light filled-container style, not a bare outline.

When a session still needs more participants, the blocking notice keeps **Invite** at every size but drops **pick a different activity** at the minimized rest — it only navigates away and wouldn't fit the short sheet — restoring it once the sheet is maximized (and always on web).

**On web** the CTA section is a vertical list carrying the same colour hierarchy as the mobile row: exactly one **primary** (darker, filled) action on top — chosen by the same ongoing → Join → Start rule — with every following action a fully filled but **lighter** (primaryContainer) button, not a bare outline. A **Completed** button joins the list on the same terms as the mobile chip. The waiting room is the one exception to the single-primary rule: ping the course, play with the bot, and invite a friend are equally valid ways forward, so none leads — every one takes the same primary fill, keeping the button colour consistent from Start through the waiting room rather than dropping to the lighter style there. There is no horizontal CTA row on web.

**Share** and **flag** do not sit in the web CTA list. **Share** is an app-bar action to the left of focus. **Flag** sits in the top-right of the text-content (description) section under the hero — so it rides the main step, not the join/completed sub-pages, where there is no description to anchor it. On mobile both stay as chips appended to the bottom CTA row.

While a confirmed session waits to fill (chat not started), a **"…"** menu takes the app-bar share slot on web — and is net-new on mobile, which has no app-bar share — offering **Leave**, plus **Delete** for the room's admin (the same exit chat gives). It displaces share here so inviting people isn't confused with sharing the link.


## Owning the container: nav rail and analytics bar

The "nav rail" is the four icons that switch page/scope — the bottom row of the mobile nav container, and its wide-screen counterpart. Normally surfaces open in the container *above* those icons, so a learner can keep navigating. The activity start page instead **takes over the container**: while it is open the four nav items are gone, and the always-present **X** on the page is the way back to them. This replaces today's behavior, where the page opened above a still-visible rail that no longer controlled anything.

At the **full** stop only, the mobile sheet covers the top **analytics bar** ([`WorldAnalyticsBar`](../../lib/routes/world/world_analytics_bar.dart)); at minimized it stays visible. Two pieces make it "cover" rather than just "hide": the sheet's full-height bound reserves neither the analytics-bar band nor the rail's (the plan hides the rail), so it grows up into that space; and the bar fades out — kept mounted so it doesn't re-fetch — while the sheet is full. The signal is the nav cavity's `onCavityFullChanged`, published for the activity only through [`ActivitySheetFull`](../../lib/routes/world/map_context.dart) and read by the shell ([`workspace_shell.dart`](../../lib/widgets/layouts/workspace_shell.dart)). This is mobile-only: on the wide web panel the analytics cluster ([`WorldUserCluster`](../../lib/routes/world/world_user_cluster.dart)) stays beside the fixed panel, which has no maximize.

Even at full the page stays **inset with rounded corners over the map** — it is overlaid on the map, never true edge-to-edge fullscreen, on either platform. This is what keeps it feeling like a map panel rather than the chat view (which does take the whole screen). Reaching a genuine subpage from here — opening a chat — is the one case that leaves this panel model for the full-screen chat surface with its own back control.
