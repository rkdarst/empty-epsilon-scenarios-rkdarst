# Sources and lookups

Where an answer lives, and the one-liners that find it in the vendored release.

## Primary sources, in usefulness order

| Source | Where | Notes |
|---|---|---|
| **API reference (version-correct)** | `find vendor -name script_reference.html` | authoritative for the pinned build. Online copy of the *current* build: <http://daid.eu/dump/script_reference.html> |
| Official scripting tutorial | <https://daid.github.io/EmptyEpsilon/#tabs=4> | builds "Beacon of Light"; the shipped result is `scripts/scenario_05_beacon.lua` |
| Shipped example scenarios | `vendor/EE-*/**/scripts/scenario_*.lua` | ~35 official ones — the only runnable API examples that match your version |
| Server-side Lua libs | same `scripts/` dir: `ee.lua` (`SYSTEMS`, `ALERT_LEVELS`, `MISSILE_TYPES`), `utils.lua`, `luax.lua`, `factionInfo.lua`, `science_db.lua`, `shiptemplates/` | `require`-able server side |
| Shipped comms scripts | `scripts/comms_station.lua`, `comms_ship.lua`, `comms_scenario_utility.lua` | default hail behaviour, overridable via `setCommsScript`/`setCommsFunction` |
| Wiki | <https://github.com/daid/EmptyEpsilon/wiki> | esp. *Scenario Scripting*, *Fallback Content Paths*, *Headless Dedicated Server*, *Preferences file* |
| Engine source | <https://github.com/daid/EmptyEpsilon> (`src/scenarioInfo.cpp`, `src/script/`, `src/ai/`, `scripts/`) | where behaviour and docs disagree, this wins |
| Networking/interest management | <https://github.com/daid/SeriousProton> | *who receives which objects* lives here, not in the game repo |
| Reference generator | game repo `script_docs/` | `script_reference.html` is generated from C++ annotations, so it can lag the code |

Re-fetch the engine source to verify behaviour (the `.deb` strips it):

```sh
git clone --depth 1 --branch EE-2024.12.08 --filter=blob:none --sparse \
    https://github.com/daid/EmptyEpsilon /tmp/ee-src
git -C /tmp/ee-src sparse-checkout set src scripts
```

Pin the tag to the vendored release (note the `EE-` prefix), otherwise you will
"verify" against an API you do not have. The scripting glue lives partly in
[SeriousProton](https://github.com/daid/SeriousProton) (sibling repo at build
time, **not pinned** by the EmptyEpsilon repo), so for claims about callback
storage/upvalue validation the exact SeriousProton revision that built the
`.deb` is unrecorded - verify those against the deb's *behaviour* and tag them
`[obs]` rather than `[src]`.

## One-liners against the vendored release

```sh
DATA=$(find vendor/EE-* -path '*/scripts/scenario_00_basic.lua' | sed 's|/scenario_00_basic.lua||')
REF=$(find vendor -name script_reference.html | head -1)

# every ship template name this build knows
grep -rhoP 'setTemplate\("\K[^"]+' "$DATA"/shiptemplates/*.lua | sort -u

# real usage of an API call, from the official examples
grep -rn "setCommsFunction" "$DATA"/scenario_*.lua | head

# signature + doc + example for one call, straight out of the reference
grep -oP '.{100}getObjectsInRadius.{220}' "$REF"

# station/model radii (the numbers geometry maths depends on)
grep -n "space_station" "$DATA"/model_data.lua | head

# which factions exist
grep -oP '"\K[A-Z][A-Za-z ]+(?=")' "$DATA"/factionInfo.lua | sort -u | head -20
```

The last three are the ones that settle most arguments: template names, hull
radii, faction spellings. A faction name that does not exist in `factionInfo.lua`
is silently treated as a new faction with default relations - which looks like a
radar bug. `[obs]`

## Releases

<https://github.com/daid/EmptyEpsilon/releases> — stable tags `EE-YYYY.MM.DD`,
testing tags `EE-…PR`; Linux asset is a `.deb` (`bin/ee_get.sh` unpacks it
without root). Newer PR builds can add API and change AI/radar details, so when
`EE_TAG` changes: run `bin/ee_selftest.sh`, then re-check any `[obs]` claim your
scenario leans on.

## Community snippets: how to read them

Discord/Reddit/forum examples are useful for *intent* and unreliable for *API*:
they are usually written against whatever the author's build was, and names move
between releases. Before pasting one:

1. grep the call name in the vendored `script_reference.html` (one-liner above) —
   if it is absent, the function does not exist in your build (typical example:
   damage-multiplier setters that only newer builds have; the pattern to use
   instead is in [patterns/tuning-knobs.md](../patterns/tuning-knobs.md));
2. check the same call's *argument count and order*, which is where silent
   breakage hides — a call that exists with a different arity fails at runtime,
   not at load;
3. treat any behaviour claim ("nebulae hide ships from everything", "destroy()
   triggers onDestruction") as a hypothesis and run the 20-line probe in
   [testing/runtime-surprises.md](../testing/runtime-surprises.md) before
   repeating it. `[obs]`

Official places worth searching: the game's own `scripts/` examples (version
matched), the wiki, and the engine source. Everything else needs the three checks
above.
