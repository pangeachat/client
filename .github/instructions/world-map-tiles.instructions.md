---
applyTo: "lib/routes/world/**"
description: "World map tile strategy — phased plan from free hosted tiles, to self-hosted, to custom-themed tiles."
---

# World Map Tiles

The world map's base tiles are both a cost surface (providers bill per request or per map load) and a brand surface (how the map looks). This is the phased plan; the current source is [the map widget](../../lib/routes/world/world_map.dart).

## Phase 1 — Free hosted tiles (current)

Free hosted raster tiles, switched by the app theme: **OpenStreetMap** standard for light, **CartoDB Dark Matter** for dark. Rationale: zero cost and zero setup at our current scale (~100 MAU). Limits we accept for now: raw public tiles aren't sanctioned for a commercial product at scale, and free tiers cap somewhere in the low hundreds of active map users — fine today, not for the growth runway. Tiles are fetched directly from the provider CDN, never proxied through a backend.

## Phase 2 — Self-host

Move to self-hosted vector tiles. Rationale: a flat, low monthly cost independent of user count, which removes both the usage-policy exposure and the free-tier ceiling, and means we own the stack rather than renting it. Trigger to migrate: when Phase 1's free tiers run out (low hundreds of active users), or ahead of the ACTFL visual push — whichever comes first.

A concrete goal that vector unlocks: **bright, legible, on-brand labels at no extra cost.** On vector, label colour and weight are client-side style properties. On Phase 1 raster the labels are baked into the tile, so lifting just them needs a second labels layer that doubles tile requests — not worth paying for. Vector makes readable labels a styling choice, not a network cost.

## Phase 3 — Custom visual theming

Style the tiles to the Pangea travel brand instead of an off-the-shelf look. At this point we will likely also restrict the zoom levels and the geographic areas a learner can see — both to keep the tileset small and cheap, and as a travel/progression mechanic where the world opens up as the learner advances.

## Future Work

- Self-host migration, custom map style, and zoom/location gating — file and link GitHub issues as each is scheduled.
