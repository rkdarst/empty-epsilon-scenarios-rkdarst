# Runner anatomy — what actually executes

Worth understanding before you debug a runner, because three engine facts shape
all of them. `[src]` `[obs]`

## Fact 1: the whole scenario is one Lua chunk

EE concatenates every `.lua` in a scanned scripts directory into a single chunk,
and a scenario file is itself one anonymous chunk. So a driver *appended after
the scenario file* is in the same scope and can see its `local` helpers - which
is how a test can call `lc_eject_ok()` or `commsLumina_replies()` without the
scenario exposing anything. It is also why test drivers must never be *dropped
into* the scripts dir as separate files: another file in the same directory
shares global scope and can collide with the scenario's names.

## Fact 2: the game is a stateful client

* It **always** binds TCP+UDP 35666 at boot (the `server_port` argument does not
  move that listener), and **segfaults** if the bind fails. The runners therefore
  check the port first and, if it is taken, run the game inside a private network
  namespace (`unshare -rn`) or stop with exit 4. `[obs]`
* Because that port is machine-global, the runners take a **lock**
  (`$EE_LOCK`, default `/tmp/ee-headless.lock`) for the duration of a run: two
  runs started at the same moment would otherwise both pass the "port free"
  probe and the loser would crash. A second run therefore *waits* for the first
  (`EE_LOCK_TIMEOUT`, default 1800 s, then exit 4). `[obs]`
* `headless=<file>` starts the game with that scenario, **paused**. `startpaused=1`
  keeps it paused; omitting it lets the world run.
* The binary resolves `resources/`, `scripts/` and `packs/` from its **CWD**, so
  the runner must `cd` into the release's data directory; custom scenarios come
  from `~/.emptyepsilon/scripts` (or `EE_CONF_DIR`).
* `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy` are what make a headless run
  work on a machine with no GPU or sound card.

## Fact 3: script output is only in the log

Everything the scenario `print()`s arrives as `INFO: LUA: ...`. A runner's job is
therefore: build a throwaway `HOME`, assemble the file, boot, wait for
`Load script: <file>`, let it run, then grep. The throwaway dir is
`mktemp -d` with a trap, so parallel runs never fight over state.

## The two runners

| | `ee_smoke.sh` | `ee_func.sh` |
|---|---|---|
| boots | paused (`startpaused=1`) | running |
| runs | `init()` + a few ticks | the whole mission |
| duration | load + `SMOKE_SETTLE` (4 s) | until the driver's end marker or `RUNTIME` |
| checks | log patterns | assertion markers |
| catches | syntax errors, `init()` crashes, bad headers, nil calls at boot | mission logic, geometry, dialog contracts, softlocks |
| cost | ~25 s | 1-4 min (driver-dependent) |

`ee_smoke.sh` is the one that should run on every edit; `ee_func.sh` is the one
that means anything.

## Error patterns the smoke test greps

```
script error            scenario runtime error reported by the engine
attempt to (call|index|perform)   the Lua nil/bad-op family
error loading           the loader rejected the chunk
Unknown scenario meta data        header typo (parsed BEFORE the Lua runs)
No scenario category              header has no Type: line
```

Two known blind spots, both because the engine logs them without matching those
patterns: the *scenario-name* line for a bad header, and a Lua syntax error line
that the loader reports once at load. **Always skim the log excerpt** the smoke
test prints, and confirm you see `Load script: <file>` plus your `init()` line.

## Scenario settings in a headless run

`Setting[...]` values cannot be *chosen* headlessly (the choice UI is the GUI
server-creation dialog; a plain headless boot applies only the `|Default`
value), so `ee_func.sh` can inject any values you want:

```sh
EE_SETTINGS="Difficulty=Story;EnemyCount=Hard" ee_func.sh scenarios/x.lua
```

It writes a prelude *before* the scenario in the concatenated chunk that shadows
the reader, so even a top-level `local diff = getScenarioSetting("Difficulty")`
sees the override:

```lua
do
  local real, over = getScenarioSetting, { ["Difficulty"] = "Story", ["EnemyCount"] = "Hard" }
  getScenarioSetting = function(k) local v = over[k]
      if v ~= nil then return v end return real(k) end
end
```

Consequences worth remembering:

* the prelude is generated per run, so nothing stale can leak from a previous run;
* run your suite once per meaningful setting combination - a difficulty branch that
  is never polled is a branch that will be broken;
* there is no options API to shadow (`getScenarioOption` does not exist in
  2024.12.08 - booleans are two-value `Setting[Key]` dropdowns), and testing a
  setting's *absence* is simply omitting it. `[obs]`

## End/exit markers `ee_func.sh` waits for


* `EE-AUTOTEST done:` — the generic harness finished (see
  [writing-drivers.md](writing-drivers.md)).
* `EE-ASSERT FAIL|ERROR` — an assertion failed; exit 1.
* Legacy `LC-ASSERT` / `LC-AUTOTEST` markers are still recognised so older
  drivers work unchanged.
* `mission complete - victory declared` — the mission ended on its own; treated as
  "finished", not as "passed", unless no assertion failed.

## Environment knobs

| Var | Meaning |
|---|---|
| `EE_VENDOR` | where `EE-*/` releases live (auto-detected from repo/package/cache) |
| `EE_SCENARIO_DIR` | scenario dir exposed to the game / to `ee_play.sh` |
| `EE_ROOT` | project root, for driver discovery (`$EE_ROOT/tests/<name>.autotest.lua`) |
| `AUTOTEST` | driver path; `none` = boot and idle only |
| `EE_SETTINGS` | `K=V;K2=V2` injected as `getScenarioSetting` overrides |
| `RUNTIME` / `SMOKE_TIMEOUT` / `SMOKE_SETTLE` / `GAP` | timing |
| `EE_LOCK` / `EE_LOCK_TIMEOUT` | runner lock file / wait time (see below) |
| `SMOKE_EE_TAG` / `EE_TAG` | pin a vendored release |

`RUNTIME` is wall-clock seconds, and a headless world advances about one game
second per second: it must be **larger than the last `ee_step()` time plus its
`ee_until()` deadline**, or the run ends with `driver never finished` (exit 1) even
though every assertion that ran passed. `[obs]`

Rather than remembering to grow it, let the driver declare its own length with a
header line — `-- ee_runtime: 80` — which `ee_func.sh` uses as the default when
`RUNTIME` is not set (an explicit `RUNTIME=N` still wins). A driver whose
timeline grows then carries its own timeout in the file that describes the
timeline. `[obs]`

## One run at a time

Because headless EE always binds 35666, the runners serialise themselves on a
machine-wide lock (`/tmp/ee-headless.lock`, override with `EE_LOCK`): a second
invocation waits instead of segfaulting on the port. That is intentional — start
long drivers sequentially, or point the second run at another machine / set
`EE_NS`. `EE_LOCK_TIMEOUT` (default 1800 s) bounds the wait with exit 4. `[obs]`

Two things used to make a queue of runs crawl instead of hand off, both fixed in
the runners, both worth knowing when a run seems to hang before it starts: `[obs]`

* A headless game started under `EE_NS` is a *child* of the netns wrapper, and
  the wrapper reaps it from an `EXIT` trap. `kill -9` skips traps, so the game
  survived its runner, reparented to PID 1, and kept serving 35666. The runners
  now `kill -TERM` first, wait briefly, then `pkill -P` the child before the
  final `kill -9`.
* The lock lives on fd 9 of the runner shell, and fd 9 was inherited by the game
  — so an orphan kept the *lock*, not just the port, and every later run then sat
  in `flock` for up to `EE_LOCK_TIMEOUT`. Both launch lines now close it for the
  child (`9>&-`), which makes an orphan harmless by construction.

Symptom to recognise: the runner prints nothing for minutes, and
`ps -eo pid,ppid,comm | grep EmptyEpsilon` shows a game whose `PPid` is 1. Kill
it; the queue resumes immediately. `[obs]`
