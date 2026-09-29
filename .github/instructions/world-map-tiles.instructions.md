---
applyTo: "lib/routes/world/**,lib/routes/chat/map_bubble.dart"
description: "World map tile strategy — phased plan from OpenStreetMap's free tiles, to a paid hosted provider, to self-hosted vector tiles in a Pangea style."
---

# World Map Tiles

The world map's base tiles are both a cost surface (providers bill per request or per map load) and a brand surface (how the map looks). This is the phased plan; the current source is [the map widget](../../lib/routes/world/world_map.dart). The location bubble in chat ([`map_bubble.dart`](../../lib/routes/chat/map_bubble.dart)) draws from the same provider and follows the same plan.

## Phase 1 — OpenStreetMap's free tiles (current)

Free raster tiles from **OpenStreetMap**'s standard layer for both themes. Dark theme is a client-side color filter (flutter_map's dark color matrix, applied once over the whole tile layer — per-tile application measured roughly double the frame cost, #8623), so it adds no tile requests. A single provider means a single failure mode — the previous dark provider (CartoDB Dark Matter's keyless CDN) served "API KEY REQUIRED" watermark tiles to some users (#8585). Tiles are fetched directly from the provider, never proxied through a backend.

Limits we accept while on it:

- OSM's [tile usage policy](https://operations.osmfoundation.org/policies/tiles/) says a commercial app's access may be withdrawn at any point, and it publishes no threshold to plan against.
- The policy asks each app to identify itself in its User-Agent. Native builds do; browsers don't let web code set that header, so web traffic can't comply.
- OSM rate-limits per IP address, so the first thing likely to break is one school: many students opening the map at once behind a shared network. Total user count matters far less.
- Filtered-OSM dark is functional rather than on-brand.

**Blocking detection and its limit (#8603).** Tile-load failures (`TileLayer.errorTileCallback`, with non-2xx responses treated as hard errors rather than optimistically decoded) are split by what they mean: an HTTP error status — the provider answering "no", the blocking signature — escalates to one Sentry warning event per app session, so a block is visible (and alertable) across sessions; network-level failures are the user's own connectivity and leave only a rate-limited breadcrumb, so an offline learner never generates events. Either way the failed tile degrades to the themed map background instead of flashing. What no cheap check can catch is a provider serving *wrong* tiles with HTTP 200 — exactly #8585's watermark mode. Detecting that would mean pixel-inspecting tiles against a reference, so recurrence of that class is caught only by human eyes on the map; do not read the telemetry as covering it.

## Phase 2 — Paid hosted raster tiles

The same raster tiles, from a provider licensed for commercial use: **Stadia Maps**, on a paid plan. Hosted providers' free tiers are non-commercial only, so there is no free step between Phase 1 and this one. Stadia because it bills per tile request, which suits how the map is used, and ships its own dark style, which replaces the client-side dark filter.

Hosted raster comes before self-hosting because it is only a change of tile address and key: flutter_map already renders raster. Self-hosting pays off only with vector tiles, which need a new map renderer in the client — the Phase 3 investment.

Switch ahead of a block, not in response to one. Changing the tile provider ships in a client release, so after a block the affected learners — likely a whole school — would see a blank map until new app-store builds are approved.

## Phase 3 — Self-hosted vector tiles in a Pangea style

Self-hosted vector tiles, styled to the Pangea travel brand instead of an off-the-shelf look. Rationale: a flat, low monthly cost that doesn't grow with users, and we own the stack rather than renting it. Trigger: when the map's look becomes a product priority.

A concrete goal that vector unlocks: **bright, legible, on-brand labels at no extra cost.** On vector, label colour and weight are client-side style properties. On raster the labels are baked into the tile, so lifting just them needs a second labels layer that doubles tile requests — not worth paying for.

At this point we will likely also restrict the zoom levels and the geographic areas a learner can see — both to keep the tileset small and cheap, and as a travel/progression mechanic where the world opens up as the learner advances.
