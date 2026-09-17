---
applyTo: "lib/routes/world/**"
description: "World map tile strategy — phased plan from free hosted tiles, to self-hosted, to custom-themed tiles."
---

# World Map Tiles

The world map's base tiles are both a cost surface (providers bill per request or per map load) and a brand surface (how the map looks). This is the phased plan; the current source is [the map widget](../../lib/routes/world/world_map.dart).

## Phase 1 — Free hosted tiles (current)

Free hosted raster tiles: **OpenStreetMap** standard for both themes, with dark theme rendered as a client-side color filter (flutter_map's `darkModeTileBuilder`) over the same tiles. Rationale: zero cost and zero setup at our current scale (~100 MAU), and a single provider means a single failure mode and usage budget — the previous dark provider (CartoDB Dark Matter's keyless CDN) enforced per-IP usage by serving "API KEY REQUIRED" watermark tiles to some users (#8585). Limits we accept for now: raw public tiles aren't sanctioned for a commercial product at scale, free tiers cap somewhere in the low hundreds of active map users, and filtered-OSM dark is functional rather than on-brand — fine today, not for the growth runway. Tiles are fetched directly from the provider CDN, never proxied through a backend.

**Blocking detection and its limit (#8603).** Tile-load failures (`TileLayer.errorTileCallback`, with non-2xx responses treated as hard errors rather than optimistically decoded) are split by what they mean: an HTTP error status — the provider answering "no", the blocking signature — escalates to one Sentry warning event per app session, so a block is visible (and alertable) across sessions; network-level failures are the user's own connectivity and leave only a rate-limited breadcrumb, so an offline learner never generates events. Either way the failed tile degrades to the themed map background instead of flashing. What no cheap check can catch is a provider serving *wrong* tiles with HTTP 200 — exactly #8585's watermark mode. Detecting that would mean pixel-inspecting tiles against a reference, so recurrence of that class is caught only by human eyes on the map; do not read the telemetry as covering it.

## Phase 2 — Self-host

Move to self-hosted vector tiles. Rationale: a flat, low monthly cost independent of user count, which removes both the usage-policy exposure and the free-tier ceiling, and means we own the stack rather than renting it. Trigger to migrate: when Phase 1's free tiers run out (low hundreds of active users), or ahead of the ACTFL visual push — whichever comes first.

A concrete goal that vector unlocks: **bright, legible, on-brand labels at no extra cost.** On vector, label colour and weight are client-side style properties. On Phase 1 raster the labels are baked into the tile, so lifting just them needs a second labels layer that doubles tile requests — not worth paying for. Vector makes readable labels a styling choice, not a network cost.

## Phase 3 — Custom visual theming

Style the tiles to the Pangea travel brand instead of an off-the-shelf look. At this point we will likely also restrict the zoom levels and the geographic areas a learner can see — both to keep the tileset small and cheap, and as a travel/progression mechanic where the world opens up as the learner advances.

## Future Work

- Self-host migration, custom map style, and zoom/location gating — file and link GitHub issues as each is scheduled.
