# ee-skills — agent guide

Portable Empty Epsilon scenario-authoring knowledge and tooling. Verified against
**EE-2024.12.08**; every factual claim in `reference/` is tagged
`[src]`/`[ref]`/`[obs]`/`[infer]` (see [reference/README.md](reference/README.md)).

## Rules that matter

1. A scenario is **one Lua file** named `scenario_<NN>_<name>.lua` (the game globs
   `scenario_*.lua`). Nothing else registers it.
2. The `--` **header block is parsed before the Lua runs**: a missing `Type:`
   silently files the mission under *Unknown*. Grammar:
   [authoring/HEADER-FORMAT.md](authoring/HEADER-FORMAT.md).
3. Code lives in `init()` (build the world, once) and `update(delta)` (every tick:
   poll, watch, advance phases). Poll, never sample.
4. **Validate with the game, not by eye**: `bin/ee_smoke.sh <file>` (25 s boot
   check) and `bin/ee_func.sh <file>` (full mission with an assertion driver).
5. Before inventing a "the players must not see this yet" or "this must always
   drop" mechanic, read
   [reference/runtime-pitfalls.md](reference/runtime-pitfalls.md) — same-faction
   objects are always visible, `onDestruction` fires only on damage kills,
   artifacts never advance scan states, and station hull radii decide what
   "alongside" means.
6. Before adding a Gamemaster console layer, read
   [patterns/gm-console.md](patterns/gm-console.md): one `addGMFunction` call is
   one button (paging is a script convention), a callback whose first upvalue is
   not the globals table fails at registration, and a label gets about **20
   characters** in a fixed-width cell that centers it — so a long label loses its
   own verb.
7. The API reference of the pinned build is `script_reference.html` inside the
   vendored release: `find vendor -name script_reference.html`.

## The five commands

```sh
bin/ee_bootstrap.sh          # one-time: game + runtime libs, then prove it works
bin/ee_smoke.sh  <file.lua>  # every edit: boot check (~25 s)
bin/ee_func.sh   <file.lua>  # full-mission assertion driver (1-4 min)
bin/ee_selftest.sh           # prove the package is self-sufficient (no repo files)
bin/ee_play.sh               # play it graphically (Apptainer, host home hidden)
```

All of them accept `EE_VENDOR` / `EE_ROOT` / `EE_SCENARIO_DIR` to point at a
project elsewhere; drivers are found at `$EE_ROOT/tests/<scenario>.autotest.lua`
(or `AUTOTEST=path`), and `EE_SETTINGS="Key=Value;…"` injects scenario settings a
headless boot can never receive from the GUI.

## Layout

| Path | Purpose |
|---|---|
| [reference/](reference/) | verified engine behaviour (scripting, pitfalls, sensors, geometry, AI, quirks) |
| [patterns/](patterns/) | recipe per recurring problem, each with code + test + pitfalls |
| [authoring/](authoring/) | header grammar, brief→code pipeline, flow diagrams, anti-softlock, player communication |
| [testing/](testing/) | runner anatomy, driver authoring, runtime surprises, human acceptance |
| [templates/](templates/) | scenario skeleton, driver skeleton, mission-brief template |
| [bin/](bin/) | the tooling (`ee_env.sh` holds the shared discovery logic) |
| [lib/autotest.lua](lib/autotest.lua) | generic assertion harness, concatenated at test time |
| [examples/demo/](examples/demo/) | complete mini-mission + driver = the package's acceptance test |

## Extending this package

* New engine fact → into the right `reference/` file **with a tag and how to
  re-verify it**; if it contradicts an existing claim, correct the claim and note
  the version.
* New mechanic → a `patterns/` recipe: problem, facts, code, how to test, variants.
  Add a line to [patterns/README.md](patterns/README.md).
* Anything that only holds for one project (mission text, balance numbers, design
  docs) does **not** belong here — it belongs in that project's repo.
