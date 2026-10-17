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
| `-- Type:` (or `Category:`) | category (Mission / Skirmish / …) | **missing ⇒ "No scenario category" ⇒ listed under Unknown** |
| `-- Setting[Key]: description` | declares a dropdown, filled by the following `Key[Value]` or `Key[Value|Default]: note` lines | read by `getScenarioSetting("Key")` |
| `-- Variation[Value]: note` | legacy pre-Setting syntax for a "variation" dropdown | still parsed; prefer `Setting[...]` |

There is **no `Option:` metadata and no `getScenarioOption()`** in 2024.12.08:
the parser special-cases only Name/Description/Author/Type/Category/Variation/
Setting, so `-- Option: X` and `-- Option[Name]: note` fall through to
`WARN: Unknown scenario meta data`. A boolean choice is just a two-value
`Setting[Key]` dropdown. `[src]` (`src/scenarioInfo.cpp`, `addKeyValue`)

Rules that bite:

* The long-text prefix is exactly `--- `. The space after `--` is convention,
  not grammar: the parser strips each line before splitting on the first `:`,
  so `--Name: X` parses the same as `-- Name: X`. Keep the space anyway so the
  header stays greppable. `[src]`
* An unrecognised key — including a bare `Option:` — logs
  `WARN: Unknown scenario meta data: …`, and the smoke test fails on that line,
  because it always means a typo in a key you meant to use. `[src]` `[obs]`
* A `Setting[Key]` with no following `Key[...]` value lines renders as an empty
  dropdown; a `Key[Value]` line without a preceding `Setting[Key]` has nothing
  to attach to and **logs the same WARN** — it is not silently inert. `[src]`
* Mark exactly one value `Key[Value|Default]`. A **headless boot applies the
  marked default** (`GameGlobalInfo::setScenarioSettings` assigns
  `default_option` before any Lua runs — the boot log even prints
  `Difficulty scenario setting set to Normal`); if no value is marked, headless
  reads `""` — the "first is the default" behaviour exists only in the GUI
  dropdown's display. `[src]` `[obs]`
* **Nothing delivers the non-default values headlessly** — they arrive from the
  GUI, or from `EE_SETTINGS="Key=Value"` (see
  [testing/runner-anatomy.md](../testing/runner-anatomy.md)). `[obs]`

## Defensive reading

```lua
local DIFF = getScenarioSetting("Difficulty")
if DIFF == nil or DIFF == "" then DIFF = "Normal" end     -- headless / old saves
```

Never `if getScenarioSetting("X") == "Story"` without the default line: for an
undeclared or unmarked setting the engine returns `""` (empty string, never
nil — gameGlobalInfo.cpp:529), and a nil comparison silently picks the wrong
branch, which is precisely when you are testing. `[src]` `[obs]`

## Checklist before a commit

1. `Name`, `Description`, `Type` present, prefixes exact.
2. Every `Setting[...]` has ≥2 value lines and one `|Default`.
3. `getScenarioSetting` reads guarded by a default.
4. `ee-smoke.sh` prints no `Unknown scenario meta data` / `No scenario category`.
