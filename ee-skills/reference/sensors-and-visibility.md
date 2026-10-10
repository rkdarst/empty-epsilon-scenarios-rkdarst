# Sensors, visibility and hiding things

## The two radar layers

| Layer | Default range | What reaches it | What blocks it |
|---|---|---|---|
| Long-range (sector map contacts) | whole sector chain the ship can see | everything, everywhere | **nebulae** - a cloud shadows what is behind it |
| Short-range (local radar) | ~5000 units = 5u | everything inside range, including inside nebulae | nothing |

Both layers respect an object's radar signature triple
(`setRadarSignatureBiological/Electrical/Gravity`); zeroing all three removes the
object from **both** layers, which is usually *more* than you want. `[src]` `[obs]`

## Faction is the real visibility switch

Objects of the crew's own faction are always on their contact list, at any
distance, nebula or not - the client lists them independently of radar. So:

* an invisible *friendly* station is impossible while it stays friendly;
* making it `Independent` (or any non-crew faction) removes it from the list, and
  a zeroed short-range radar also removes it from the local view;
* the reveal is just the reverse: restore the faction (and the 5000-unit radar).

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
  radius (~5u). Overlapping clouds read as one mass, so a "search area" of N
  spaced clouds is far more legible than a random scatter. `[obs]`
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
| visual/label pickup range | a few u (and `isDocked` needs < 0.5u) |
| station comms range | unlimited (they are contacts), but see the hand-over gate below |
| long-range contact list | same-faction = always; others = line of sight unshadowed by nebulae |

Design consequence: a "come closer" gate that is tighter than ~1u feels broken,
and one looser than ~5u triggers before the player believes they arrived. See
[geometry-and-units.md](geometry-and-units.md).
