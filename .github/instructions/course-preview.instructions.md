---
applyTo: "lib/routes/courses/**,lib/routes/world/course_preview_banner.dart"
description: "The course preview — tapping a course in the add-course lists rests the page low over a map scoped to that course's activities, so seeing the course on the map is the join/create decision surface."
---

# Course Preview

Tapping a course in the add-course lists (browse public / start my own) should sell the decision visually: the map behind the page becomes a preview of that course — its activities as live pins — while the page carries the plan details and the join/create action (#7826).

## The flow

- The **lists open at full height** on narrow — nothing behind them matters yet ([routing.instructions.md](routing.instructions.md), #8659).
- **Tapping a course** pushes the preview. On narrow the sheet drops to a low rest so the map leads (the activity start page's pattern — [activity-start-page.instructions.md](activity-start-page.instructions.md)); it hides the nav rail, never remembers a manual resize, and dragging it down pops back to the list. On wide the whole flow is **one panel**: the add-course hub always folds behind its subpage ([`PanelDef.stacksOnParent`](../../lib/features/navigation/panel_registry.dart)), so the map keeps the width a second panel would claim and the subpage closes with a back arrow to the hub.
- The **map scopes to the previewed course before joining** ([`CoursePreviewMapContext`](../../lib/routes/world/map_context.dart)). The own flow's plan id rides the URL token; the browse flow's resolves once the room summary lands ([`CoursePreviewPlans`](../../lib/routes/world/map_context.dart)), so the browse map re-scopes a beat after the page opens.
- The camera **auto-fits all the course's activities** into the exposed map above/beside the page — the deliberate exception to "the camera never moves for a course" ([world-map.instructions.md](world-map.instructions.md), #7616), because previewing is itself the explicit "show me this course" act.
- A **"Course preview" pill** ([`CoursePreviewBanner`](../../lib/routes/world/course_preview_banner.dart)) floats top-center over the exposed map — the one label for the mode; tapping it re-runs the fit after the learner pans away. The map search bar/overlay hides while the scope holds.
- **Pins are inert**: they still promote and demote through the normal dot/mid/large tiers as the learner pans and zooms — that is the preview — but tapping never opens an activity page, which would navigate away from the join decision.

## The page

[`SelectedCourseView`](../../lib/routes/courses/own/selected_course_view.dart) — shared by the browse preview, the start-my-own selection, and add-course-to-space:

- **Header**: the same course tile the learner tapped in the list (avatar, title, lock icon, member + info chips; no border, since it no longer navigates), with the back button to its left. At the minimized rest the title ellipsizes at one line — a wrapped title can overflow the short sheet; the tile's two-line wrap returns once expanded.
- **Pinned CTA row** at the bottom ([`CourseCtaRow`](../../lib/routes/courses/course_cta_row.dart), the activity footer's pill styling): Join, Knock, or Create course. A knock preview shows only the knock primary — class-code entry stays on its own page.
- **Scrollable middle**, dropped entirely at the minimized rest (grow-before-scroll): the course description, its admins, and the read-only course plan ([`CourseObjectivesList`](../../lib/routes/courses/course_objectives/course_objectives_view.dart) in preview mode — Missions with activity carousels, no completion overlay, no taps).

## After creating (own flow)

The invite step opens at **full height deterministically** — it never inherits a height the learner dragged the list or preview to. Its footer is a stacked CTA column ([`CourseCtaColumn`](../../lib/routes/courses/course_cta_row.dart)) with **both actions primary**: inviting friends and playing with the AI are equally valid ways forward from a fresh course, the same exception to the single-primary rule the activity waiting room makes ([activity-start-page.instructions.md](activity-start-page.instructions.md)).
