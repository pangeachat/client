---
applyTo: "lib/routes/chat/activity_sessions/**,lib/routes/world/**,lib/widgets/layouts/mobile_nav_widget.dart,lib/widgets/layouts/workspace_shell.dart"
description: "The activity start page's layout and interaction: the mobile grow-before-scroll sheet, the header + info row, the CTA row, and how the page owns its container over the nav rail and analytics bar."
---

# Activity Start Page

The start page is the panel a learner opens by tapping an activity — from a map pin or from a course plan. Its lifecycle (which step it shows, driven by the room) is [activities.instructions.md](activities.instructions.md#the-start-page-mirrors-the-room); this doc owns only its **layout and gestures**: how it fills its container, what the top of it shows, and how the buttons lay out.

One widget renders in two hosts, and the platform difference lives in the host, not the page: on narrow screens it is the swipe-expandable sheet inside the mobile nav container ([`MobileNavWidget`](../../lib/widgets/layouts/mobile_nav_widget.dart)); on wide screens it is a floating card beside the map ([`WorkspaceLeftPanel`](../../lib/routes/world/left_panel/workspace_left_panel.dart) → [`PanelCard`](../../lib/routes/world/panel_card.dart)). Both mount [`ActivitySessionStartPage`](../../lib/routes/chat/activity_sessions/activity_session_start_page.dart) via [`LeftPanelActivityDetailsSubpage`](../../lib/routes/world/activity_detail_panel.dart). Prominence comes entirely from the container behavior below — the page owns its rounded container and, at full size, reaches over the chrome around it. It gets **no** added scrim, extra shadow, border, or accent.

## The sheet grows before it scrolls

On mobile the sheet is a Google-Maps-style draggable box with three rest stops — `collapsed`, `half`, `full` ([`NavCavityHeight`](../../lib/widgets/layouts/mobile_nav_widget.dart)) — the same stops the course menu uses; it snaps to the nearest on release. The stops are **heights**, not content columns, so which content lands at a stop is approximate and a sliver of the next element may peek — that is acceptable and preferable to snapping to a content boundary.

The one rule that governs the feel: **a drag up grows the sheet, and content only scrolls once the sheet is full.** Today a learner trying to pull the sheet up instead scrolls its content, because the inner scroll view wins the gesture arena in the cavity ([`_NavCavity`](../../lib/widgets/layouts/mobile_nav_widget.dart)). The fix: below `full`, an upward gesture that would scroll the content expands the sheet to `full` first; the inner scrollable only takes over once there is nowhere left to grow. This is the whole of the "control it like Google Maps" ask.

## Top row and info row

The top of the page is two rows, present at every size (they are what the `collapsed` stop is sized around):

- **Top row** — the activity **title**, the **focus** button, and a **close (X)** in the top-right. Focus zooms and pans the map all the way to this activity's pin — it already exists ([`activity_sessions_start_view.dart`](../../lib/routes/chat/activity_sessions/activity_sessions_start_view.dart) → [`MapCameraFocusRequests`](../../lib/routes/world/map_context.dart)); only its icon changed. The X dismisses the page (see [Owning the container](#owning-the-container-nav-rail-and-analytics-bar)).
- **Info row** — creator **avatar** and **name**, the activity **L2**, **level**, **participant count**, and the **rating**. Until learners can author their own activities the creator is fixed to the PangeaChat avatar and the name "PangeaChat". The rating reuses [`ActivityRatingMeter`](../../lib/routes/chat/activity_sessions/activity_rating_meter.dart) — the NEW pill / tinted meter — and this stays the only surface that shows it (per [activities.instructions.md](activities.instructions.md#rating-an-activity)). This row is new: those fields exist on the model but were never gathered into a header, so a map explorer sees the essentials without expanding the sheet.

Below the info row the middle content (media carousel, description, suggested vocab, role cards) is unchanged, as are the later steps of the flow (the role picker and the waiting-room actions — invite / ping / play with the bot).

## The CTA row

**On mobile** the footer is a single horizontally scrolling row, Google-Maps style. Exactly one **primary** (filled) CTA leads, followed by the other available actions, with **share** and **flag** always appended last. The primary is chosen by:

- an **ongoing** session the learner is in wins outright — it becomes the primary, and no Start or Join chip appears;
- otherwise, if any **joinable** open session exists, **Join open session** is primary (Start becomes a following chip);
- otherwise **Start** is primary.

A **Completed** chip appears only when completed sessions exist. Every chip already has a destination — the selection logic is [`_NotStartedSessionCTAButtons`](../../lib/routes/chat/activity_sessions/activity_session_button_widget.dart) and the state machine in [`activity_session_start_page.dart`](../../lib/routes/chat/activity_sessions/activity_session_start_page.dart); this change is about layout, not about adding destinations. Every non-primary chip — including share and flag — uses the light filled-container style, not a bare outline.

**On web** the CTA section keeps its current vertical layout. The only move is **share** and **flag**: they leave the app bar and become two de-emphasized bare-outline container buttons placed directly under the info row (as in the web mock). There is no horizontal CTA row on web.

Share is new to this page — today only a flag button and an unrelated in-session popup menu exist ([`ActivitySessionPopupMenu`](../../lib/routes/chat/activity_sessions/activity_session_popup_menu.dart)); it reuses the workspace-level share plumbing.

## Owning the container: nav rail and analytics bar

The "nav rail" is the four icons that switch page/scope — the bottom row of the mobile nav container, and its wide-screen counterpart. Normally surfaces open in the container *above* those icons, so a learner can keep navigating. The activity start page instead **takes over the container**: while it is open the four nav items are gone, and the always-present **X** on the page is the way back to them. This replaces today's behavior, where the page opened above a still-visible rail that no longer controlled anything.

At the **full** stop only, the page also covers the **analytics bar** — the top pill on mobile ([`WorldAnalyticsBar`](../../lib/routes/world/world_analytics_bar.dart)), the vertical cluster on wide screens ([`WorldUserCluster`](../../lib/routes/world/world_user_cluster.dart)). At `collapsed` and `half` the analytics bar stays visible. Because these paint after (above) the panel in the shell's `Stack` today ([`workspace_shell.dart`](../../lib/widgets/layouts/workspace_shell.dart)), covering them is a z-order/layout change at full size, not a rewrite.

Even at full the page stays **inset with rounded corners over the map** — it is overlaid on the map, never true edge-to-edge fullscreen, on either platform. This is what keeps it feeling like a map panel rather than the chat view (which does take the whole screen). Reaching a genuine subpage from here — opening a chat — is the one case that leaves this panel model for the full-screen chat surface with its own back control.
