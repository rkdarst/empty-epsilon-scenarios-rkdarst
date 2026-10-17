# Sensors, visibility and hiding things

## The radar layers

| Layer | Default range | Shown on | Fog of war |
|---|---|---|---|
| Long-range, science + main screen | 30000 units = 30u (`shipTemplateBasedObject.cpp`) | `NebulaFogOfWar` | an object is hidden when a nebula lies between it and the viewer *and* it is beyond the viewer's short-range radar |
| Long-range, relay screen | 30u | `FriendlysShortRangeFogOfWar` | only objects inside a *sight bubble* are drawn: friendly ships and stations (bubble = their short-range radar range), your own probes (5u), your own ship |
| Short-range (all screens) | ~5000 units = 5u | - | none - `Nebula::blockedByNebula` returns false inside the short-range distance, so the local radar always paints everything near you |

Radar signatures (`setRadarSignatureInfo(gravity, electrical, biological)`) do
not gate radar drawing in this pin. They feed the science console's raw scanner
plot (`rawScannerDataRadarOverlay.cpp`): zero signature = no scanner blip. The
engine pre-sets signatures on its own objects (wormholes read heavy on gravity,
jammers on electrical). `[src]`

## Faction is the real visibility switch

On the relay screen, every friendly ship and station is always drawn - at any
distance, nebula or not - because each one seeds its own sight bubble
(`radarView.cpp`). So:

* an invisible *friendly* station is impossible while it stays friendly;
* making it `Independent` (or any non-crew faction) removes it from the relay
  map (nothing seeds a bubble for it), and a zeroed short-range radar also
  removes it from the local view;
* the reveal is just the reverse: restore the faction (and the 5000-unit radar);
* on the science/main long-range radar faction does not matter - nebulae shadow
  any hideable object beyond short range.

Recipe: [patterns/hidden-station.md](../patterns/hidden-station.md). `[src]` `[obs]`

## Scanning and scan states

* Ships advance notscanned - simplescan - fullscan via the science scanner
  (`scanningChannelDepth`, `scanningComplexity` gate what is revealed). `[ref]`
* **Artifacts never advance** - they are created fully scanned. To get a
  "readable only up close" label you must implement the two-state yourself: write
  all four descriptions, and flip them in `update()` when a ship closes in.
  Recipe: [patterns/container-drop.md](../patterns/container-drop.md). `[src]` `[obs]`
* `isScannedBy(player)` is a reliable way to gate "have they actually looked at
  it" on ships; for artifacts use your own distance gate. `[obs]`

## Nebulae in practice

* `Nebula():setPosition(x, y)` - no size argument; the visual cloud has a fixed
  radius (~5u, `src/spaceObjects/nebula.cpp`). Overlapping clouds read as one
  mass, so a "search area" of N spaced clouds is far more legible than a random
  scatter. `[src]` `[obs]`
* A nebula does **not** hide anything at short range: flying into a cloud still
  paints everything inside it on the local radar. `[obs]`
* Load cost is real: thousands of clouds add seconds to `init()` and slow the
  client's rendering. Budget them (see [patterns/world-seeding.md](../patterns/world-seeding.md)). `[obs]`

## Making a *small* object unfindable

The useful combination for a "something is out there, go look" beat: a slow tug
with all three signatures zeroed, so it is invisible until visual range and
cannot be shot at until it is seen; a real freighter in front of it carries the
radar return and the dialogue. Recipe:
[patterns/radar-dark-tug.md](../patterns/radar-dark-tug.md). `[obs]`

## Distances the crew can actually act on

| Capability | Practical reach |
|---|---|
| short-range radar | 5u |
| visual/label pickup range | a few u (dock request range is 1u + hull radius) |
| station comms range | unlimited (they are contacts), but see the hand-over gate below |
| long-range contact list | same-faction = always; others = line of sight unshadowed by nebulae |

Design consequence: a "come closer" gate that is tighter than ~1u feels broken,
and one looser than ~5u triggers before the player believes they arrived. See
[geometry-and-units.md](geometry-and-units.md).
