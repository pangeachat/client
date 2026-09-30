---
applyTo: "lib/routes/world/**,lib/routes/chat/map_bubble.dart,lib/pangea/common/utils/map_tiles.dart"
description: "World map tile strategy — phased plan from OpenStreetMap's free tiles, to a paid hosted provider, to self-hosted vector tiles in a Pangea style."
---

# World Map Tiles

The world map's base tiles are both a cost surface (providers bill per request or per map load) and a brand surface (how the map looks). This is the phased plan. The tile source for every map lives in [`MapTiles`](../../lib/pangea/common/utils/map_tiles.dart), used by [the world map](../../lib/routes/world/world_map.dart) and by the location bubble in chat ([`map_bubble.dart`](../../lib/routes/chat/map_bubble.dart)).

## Phase 1 — OpenStreetMap's free tiles (past)

Free raster tiles from **OpenStreetMap**'s standard layer, with dark theme drawn as a client-side color filter over the same tiles. We left it ahead of any block (#8603) because OSM's [tile usage policy](https://operations.osmfoundation.org/policies/tiles/) lets it withdraw a commercial app's access at any point, publishes no threshold to plan against, and rate-limits per IP address — so the first thing likely to break was one school, many students opening the map at once behind a shared network.

## Phase 2 — Paid hosted raster tiles (current)

The same kind of raster tiles, from a provider licensed for commercial use: **Stadia Maps**, on a paid plan. Hosted providers' free tiers are non-commercial only, so there is no free step between Phase 1 and this one. Stadia because it bills per tile request, which suits how the map is used, and ships its own dark style, so dark theme needs no client-side filter.

- **Styles.** Alidade Smooth in light theme, Alidade Smooth Dark in dark theme. The map background, which shows wherever a tile hasn't loaded, matches the tiles' land colour, so a gap reads as unfilled map rather than a flash.
- **Credits.** Stadia Maps, OpenMapTiles and OpenStreetMap, each linked to its attribution page.
- **Web authenticates by domain.** Stadia checks the page's domain: `app.pangea.chat` for production, `*.staging.pangea.chat` for staging and PR previews, and localhost needs nothing. Web builds never carry the key, because the web `.env` is served publicly.
- **Native builds carry an API key.** The Android and iOS builds get it from AWS Secrets Manager at build time, one key per environment. It is sent in a request header rather than the tile URL, so it never appears in error reports.
- **Rotating a key breaks installed apps that still carry it** — their maps go blank until the user updates. Add the new key and ship builds with it before revoking the old one.

Tiles are fetched directly from Stadia, never proxied through a backend.

**Failure detection and its limit.** Tile-load failures (`TileLayer.errorTileCallback`, with non-2xx responses treated as hard errors rather than optimistically decoded) are split by what they mean. An HTTP error status is the provider answering "no" — a block, a missing key, or a domain not on the list — and escalates to one Sentry warning event per app session, so it is visible (and alertable) across sessions. Network-level failures are the user's own connectivity and leave only a rate-limited breadcrumb, so an offline learner never generates events. Either way the failed tile degrades to the map background instead of flashing. What no cheap check can catch is a provider serving *wrong* tiles with HTTP 200 — the "API KEY REQUIRED" watermark tiles a keyless provider once served (#8585). Detecting that would mean pixel-inspecting tiles against a reference, so that class is caught only by human eyes on the map; do not read the telemetry as covering it.

Hosted raster comes before self-hosting because it is only a change of tile address and key: flutter_map already renders raster. Self-hosting pays off only with vector tiles, which need a new map renderer in the client — the Phase 3 investment.

## Phase 3 — Self-hosted vector tiles in a Pangea style

Self-hosted vector tiles, styled to the Pangea travel brand instead of an off-the-shelf look. Rationale: a flat, low monthly cost that doesn't grow with users, and we own the stack rather than renting it. Trigger: when the map's look becomes a product priority.

A concrete goal that vector unlocks: **bright, legible, on-brand labels at no extra cost.** On vector, label colour and weight are client-side style properties. On raster the labels are baked into the tile, so lifting just them needs a second labels layer that doubles tile requests — not worth paying for.

At this point we will likely also restrict the zoom levels and the geographic areas a learner can see — both to keep the tileset small and cheap, and as a travel/progression mechanic where the world opens up as the learner advances.
