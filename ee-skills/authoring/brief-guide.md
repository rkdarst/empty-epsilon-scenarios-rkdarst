# Brief guide

The brief is the one place where a human's taste enters the pipeline, so it is
worth being precise about what goes in it and what "good" looks like. Full
template: [templates/design_brief.md](../templates/design_brief.md).

## Why four slots

| Slot | Question | Consumed by |
|---|---|---|
| Facts | what is true in this universe | `init()`, the knob block, the map |
| Feel | what the crew should feel | pacing, encounter density, dialog voice |
| Flavour | which nouns are allowed | every piece of player-visible text |
| Ask | what the author does not know yet | the outline's open questions |

A brief that mixes them ("it should be tense like The Expanse, about 4 sectors,
probably 3 objectives?") forces the outline author to guess which of those are
constraints and which are musings. That guessing is where missions go wrong.

## Good and bad lines

| Bad | Why | Good |
|---|---|---|
| "make it feel epic" | no action | "third act must be a defence of a place the player has visited" |
| "about 6 objectives" | count without shape | "3 mandatory, 3 optional; optional ones never gate the ending" |
| "there are nebulae" | no scale | "a 6-cloud nebula ring around the target site, ~12u radius" |
| "not too hard" | untestable | "a competent crew should win the first ambush losing no hull" |
| "hidden station" | hides it from whom? | "the crew must not know it is ours until they arrive" (→ faction flip) |

## The Ask slot is the load-bearing one

Every item in Ask must be answered in the outline as either:

* a **decision** ("3 objectives, because 5 phases × 2 sectors is already ~40 min"),
* or a **knob** ("objective count = `PART_NAMES`, tune after the first playtest"),
* or a **question back** ("do you want the defence phase to be losable? yes/no -
  it decides whether we need a defeat path at all").

Anything else (silently picking a number) is what "the agent hallucinated the
design" means in practice. The outline document must have an explicit
**Open questions** section; if it is empty, the outline author did not read the brief.

## Sizing a mission in engine units

* One sector crossing ≈ 20u ≈ 20-40 s of warp travel. `[obs]`
* A beat with travel + dialog + a fight ≈ 8-12 min of table time.
* 4-5 beats ≈ a 45-60 minute session, which is what most groups can finish.
* Nebula search: 3-6 clouds on a 10-18u ring is a fun sweep; more than ~10 clouds
  and the crew starts triangulating instead of playing. `[obs]`

Write those numbers in the brief's Facts slot, not in prose about "a lot of space".
