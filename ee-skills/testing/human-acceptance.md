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
| 11 | **GM console**: the page tree opens, every button changes something, every page returns | a button that redraws nothing = callback registration failed (`Upvalue 1 ...`, invisible in-game) |
| 12 | **GM labels** each fit their button with the verb readable (the cell centers text; over ~20 chars both ends are cut) | a label that only looks wrong on a real screen - the driver asserts the 20-char budget, the eye confirms it |

Anything that fails gets a knob change or a pattern fix, then `ee_func.sh` before
the next session.

## Notes on the client-side blind spots

* Warp transits and any timing tied to player movement cannot be observed
  headless. `[obs]`
* AI "feels" (when the enemy decides to shoot) are not verifiable headless. `[obs]`
* Visual clutter is a judgement call, and the nebula/belt densities that read
  fine on the radar map can be a white wall on screen.
* GM buttons exist only on a client screen: headless the whole GM API succeeds
  and does nothing visible, so `ee_func.sh` can prove the actions but never the
  buttons. `[obs]`

## Running a session with a GM

For a long mission, run the server headless on a box (`AUTOTEST=none` boot), then
join with a client and keep the log tail open.

* **Buttons**: the client's GM console shows the scenario's buttons. Page
  behaviour is a convention, not an API: `+Label` opens, `-Label` goes back
  ([patterns/gm-console.md](../patterns/gm-console.md)).
* **Label width**: each button is a fixed-width cell that centers its text, so a
  long label loses both ends and the verb goes with them. `*` on a dive button
  means its subject is already done. Anything a label could not hold - a
  component's exact state - is in the popup the same page shows on demand. `[obs]`
* **Console**: the LUA console executes Lua in the scenario environment - there is
  no `callscriptfunction()` in this build, so a line such as `lc_gm_status()` or
  `probe_warp_sector("E15")` *is* the call. `[obs]` In a hosted (single-process)
  game that reaches the scenario directly. Against a dedicated server the GM
  console has its own script-run path (`GameMasterActions::commandRunScript` in
  the binary) while the client-side console only evaluates locally; we have not
  verified which of the two a joined client uses. `[obs]`
* **Headless stdin is not a console**: lines piped into a headless boot are
  ignored by the engine, so a runner cannot drive the console - which is why the
  actions live in plain globals the driver can call instead. `[obs]`
* "Spawn the missing crate" during a live session is therefore a supported move:
  press the button, or type the same function the autotest calls.
