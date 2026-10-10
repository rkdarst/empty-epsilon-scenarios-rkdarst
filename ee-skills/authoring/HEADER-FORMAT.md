# Scenario header format

The header is parsed by the engine (`src/scenarioInfo.cpp`) **before** any Lua
runs, so every error in it is a *metadata* error: the script may be perfectly
fine and still be filed under "Unknown" or lose its options.

## Grammar

```
-- Name: Lost Cluster
-- Description: One line shown in the mission list.
--- Long text: the first paragraph of the briefing, shown in the detail pane.
--- Second paragraph, still part of the description block.
-- Author: scenario-dev
-- Type: Mission
-- Option: SomeFlag
-- Setting[Difficulty]: Mission difficulty.
-- Difficulty[Normal|Default]: Standard balance.
-- Difficulty[Story]: Story mode.
```

| Line | Meaning | Notes |
|---|---|---|
| `-- Name:` | mission-list name | required in practice |
| `-- Description:` | one-line description | |
| `--- ` | long description paragraphs | any `---` line adds to the block |
| `-- Author:` | author | optional |
| `-- Type:` | category (Mission / Skirmish / …) | **missing ⇒ "No scenario category" ⇒ listed under Unknown** |
| `-- Option:` / `-- Option[Name]: note` | toggle flags surfaced in the GUI, read by `getScenarioOption()` | |
| `-- Setting[Key]: description` | declares a dropdown, filled by the following `Key[Value]` or `Key[Value|Default]: note` lines | read by `getScenarioSetting("Key")` |

Rules that bite:

* The prefix is exactly `-- ` (two hyphens + space) for metadata and `--- ` for
  long text. `--Name:` (no space) is silently not metadata. `[src]`
* An unrecognised key logs `WARN: Unknown scenario meta data: …` — the smoke test
  fails on that line, because it always means a typo in a key you meant to use. `[obs]`
* A `Setting[Key]` with no following `Key[...]` value lines renders as an empty
  dropdown; a `Key[Value]` line without a preceding `Setting[Key]` is inert. `[src]`
* Mark exactly one value `Key[Value|Default]`; if none is marked, the *first* is
  the default. `[src]`
* **Nothing** delivers those values in a headless run — they arrive from the GUI.
  Test other settings with `EE_SETTINGS="Key=Value"` (see
  [testing/runner-anatomy.md](../testing/runner-anatomy.md)). `[obs]`

## Defensive reading

```lua
local DIFF = getScenarioSetting("Difficulty")
if DIFF == nil or DIFF == "" then DIFF = "Normal" end     -- headless / old saves
```

Never `if getScenarioSetting("X") == "Story"` without the default line: a nil
comparison silently picks the wrong branch on a headless boot, which is precisely
when you are testing. `[obs]`

## Checklist before a commit

1. `Name`, `Description`, `Type` present, prefixes exact.
2. Every `Setting[...]` has ≥2 value lines and one `|Default`.
3. `getScenarioSetting` reads guarded by a default.
4. `ee-smoke.sh` prints no `Unknown scenario meta data` / `No scenario category`.
