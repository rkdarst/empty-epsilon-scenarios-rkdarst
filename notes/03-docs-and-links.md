# 03 — Documentation map

## Primary sources (in usefulness order)

| Source | URL / location | Notes |
|---|---|---|
| Official scripting tutorial | <https://daid.github.io/EmptyEpsilon/#tabs=4> | "Mission scripting" tab; builds the *Beacon of Light* scenario step by step; shipped version = `scripts/scenario_05_beacon.lua` in the release |
| **API reference** | `script_reference.html` inside the release archive (vendored: `vendor/EE-*/**/script_reference.html`) | version-specific, authoritative. Online copy of current build: <http://daid.eu/dump/script_reference.html> |
| Example scenarios | `vendor/EE-*/**/scripts/scenario_*.lua` | ~40 official ones; index in `scripts/README.md` |
| Server-side Lua libs | `.../scripts/ee.lua` (constants: `SYSTEMS`, `ALERT_LEVELS`, `MISSILE_TYPES`, ...), `utils.lua`, `luax.lua`, `factionInfo.lua`, `science_db.lua`, `shiptemplates/` | `require`-able from scenarios (server-side) |
| Comms system | `.../scripts/comms_station.lua`, `comms_ship.lua`, `comms_scenario_utility.lua` | default hail behaviour; override with `setCommsScript`/`setCommsFunction` |
| Game wiki | <https://github.com/daid/EmptyEpsilon/wiki> | esp. *Scenario Scripting*, *Modding support*, *Fallback Content Paths*, *Headless Dedicated Server*, *HTTP Server*, *Preferences file*, *Creating Ship Templates*, *Translation and Localization*, *Game state logging* |
| Source of truth | <https://github.com/daid/EmptyEpsilon> (`src/scenarioInfo.cpp` header parsing, `src/script/` API impl, `src/main.cpp` startup, `scripts/` examples) | when docs and behaviour disagree, trust source + runtime |
| Reference generator | repo `script_docs/` (Python) | regenerates `script_reference.html` from C++ annotations |
| Artemis converter | repo root `artemis_mission_convert_template.lua` | converting Artemis missions |

## Community

- USN Discord (link via website "Community" tab) — main discussion, scenario
  sharing, hosted games.
- Release downloads / versions: <https://github.com/daid/EmptyEpsilon/releases>
  (stable `EE-YYYY.MM.DD`, testing `...PR`; assets: Linux `.deb`, Win `.zip`, Android `.apk`).

## Useful one-liners

```sh
# List ship templates available in the vendored version:
grep -rhoP 'setTemplate\("\K[^"]+' vendor/EE-*/usr/local/share/emptyepsilon/scripts/shiptemplates/*.lua | sort -u | head

# Find example usage of an API call in shipped scenarios:
grep -rn "sendCommsMessage" vendor/EE-*/usr/local/share/emptyepsilon/scripts/scenario_*.lua

# Re-fetch engine C++ source for behaviour verification (we don't keep a
# local mirror; the .deb strips sources):
git clone --depth 1 --filter=blob:none --sparse https://github.com/daid/EmptyEpsilon /tmp/ee-src
git -C /tmp/ee-src sparse-checkout set src scripts
```

The vendored `script_reference.html` is grep-able HTML, e.g.:

```sh
REF=vendor/EE-*/usr/local/share/doc/EmptyEpsilon/script_reference.html
grep -oP '.{100}getObjectsInRadius.{200}' $REF   # signature + doc + example
```

(Real-world catch from 2026-10: the global enumerator is
`getObjectsInRadius(x, y, radius)` — `getObjectsInRegion` does **not** exist;
our smoke test caught the mistake in the template.)
