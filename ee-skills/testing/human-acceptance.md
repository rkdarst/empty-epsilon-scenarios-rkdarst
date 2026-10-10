# Human acceptance — the 30-minute session

Headless proves the mission is *correct*. Only a client tells you whether it is
*playable*. Run this after `ee_func.sh` goes green and before you call a scenario
done; it takes one session and finds everything automation cannot.

## Setup

```sh
ee_play.sh                                   # mission menu, scenarios bound in
# or boot straight into it, paused, so the crew can read the briefing:
ee_play.sh headless=scenario_NN_name.lua     # server boot (log on stdout)
```

`ee_play.sh` runs the Apptainer image with `--contain --no-home`, binds
`scenarios/` read-only and keeps persistent options in `$EE_VENDOR/ee-state`, so
nothing about your home directory leaks into the game (and the game cannot dirty
your repo).

## The checklist

| # | Check | How it fails in real play |
|---|---|---|
| 1 | The **first notification** arrives within ~20 s of spawn | silent start, crew warps away in the wrong direction |
| 2 | **Radar census**: contacts match what the design says is discoverable | a "hidden" station is listed on the contact panel (faction flip missing) |
| 3 | Opening every **dialog page** shows text and at least one choice | blank dialog = page function errored on the client only |
| 4 | Every **choice** visibly changes something | click → same text again = the page/replies split bug |
| 5 | **Objective markers** (container labels, wreck names) are readable | label too long to read on the overview; scan state confusing |
| 6 | **Warp transit** between adjacent objectives ≤ ~30 s | map too big; travel is the mission |
| 7 | **Station approach**: coming alongside triggers the hand-over without docking gymnastics | gate radius smaller than the hull radius |
| 8 | **Nebula searches** are sweepable, not a spiral of boredom | clouds too dense (fog) or too sparse (nothing to find) |
| 9 | **Fight balance**: one squad = one engaged fight, crew hulls survive the first ambush | numbers or damage off; see the difficulty knobs |
| 10 | **Victory** ends the mission with the crew alive and the outcome stated | victory fired but the world kept spawning |

Anything that fails gets a knob change or a pattern fix, then `ee_func.sh` before
the next session.

## Notes on the client-side blind spots

* Warp transits and any timing tied to player movement cannot be observed
  headless. `[obs]`
* AI "feels" (when the enemy decides to shoot) are not verifiable headless. `[obs]`
* Visual clutter is a judgement call, and the nebula/belt densities that read
  fine on the radar map can be a white wall on screen.

## Running a session with a GM

For a long mission, run the server headless on a box (`ee_func.sh`-style boot
without the driver: `AUTOTEST=none`), then join with a client and keep the log
tail open. The scenario's `probe_*` functions are callable from the headless
console, so "spawn the missing crate" during a live session is a supported move,
not a hack.
