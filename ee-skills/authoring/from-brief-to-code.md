# Building a scenario from a brief

## The pipeline

```
   one-page brief          structured outline          one Lua file
  ----------------        ---------------------      ------------------
  templates/               agent step: outline +       init() + update()
  design_brief.md   ──▶    task graph + tuning   ──▶   + comms pages
  (facts / feel /          knobs + open                + probe_* hooks
   flavour / ask)          questions                   ──▶ ee-smoke / ee-func
```

The brief is written by a **human author**; the outline and the code are written
by an agent or developer working from the brief. The reason for the split is
that each stage has a different kind of reviewer: the brief is for "is this
mission worth playing", the outline is for "is this solvable and non-softlocking",
and the file is for "does it run".

## Why a template and not prose

[templates/design_brief.md](../templates/design_brief.md) forces four distinct
slots, and each slot maps to a different downstream consumer:

| Brief slot | Becomes |
|---|---|
| **Facts** (world state, who has what, geography) | `init()` + the tuning-knob block |
| **Feel** (what the crew should feel, pacing, references) | dialog voice, encounter density, phase beats |
| **Flavour** (nouns, tone, banned anachronisms) | the text in comms pages and notifications |
| **Ask** (what the author is unsure about) | the outline's open questions — the agent must answer or flag them, not silently pick |

A vague or contradictory brief is *allowed*: the pipeline is designed to ask its
questions early, before any Lua exists.

## Hard rules (no "as an agent")

The brief template contains rules like *"every NPC name must come from the Flavour
list or be invented and listed"* and *"never present a guess as a fact"*. Those are
written as direct imperatives, not as "the agent should…", because they are read
verbatim by whatever generates the outline — a hedged instruction gets hedged in
the output. Keep them imperative when you edit the template.

## From outline to code

The outline stage should end with something you can review in ten minutes:

1. **Phase list** with the entry condition and the exit condition of each phase,
   stated as *observable* conditions ("all three crates delivered", not "the
   players investigate").
2. **Task graph**: the beats, what each one needs to exist, and which beats can
   run in parallel. This is where you catch "phase 3 needs a ship phase 1 might
   have already destroyed".
3. **Tuning knobs**: the full knob block up front (see
   [patterns/tuning-knobs.md](../patterns/tuning-knobs.md)) with the values you
   intend to start from.
4. **Anti-softlock list**: for every "must happen", where the polling check lives.
5. **Open questions**: what you guessed. Every guess is a knob or a notification.

Then, and only then, copy [templates/scenario_skeleton.lua](../templates/scenario_skeleton.lua)
and fill it in. The order matters: knob block first, then `init()`, then the
polling `update()`, then dialogs, then `probe_*` hooks, then the driver.

## Review gates worth enforcing

| Gate | Check | Tool |
|---|---|---|
| G1 | outline has entry/exit per phase and an anti-softlock list | human |
| G2 | boots, no script errors | `ee-smoke.sh` |
| G3 | invariants at boot (counts, factions, no overlap) | driver, steps at t=2 |
| G4 | each phase's exit condition reachable headlessly | driver, one step per beat |
| G5 | no softlock: every "must happen" has a polled fallback proven by a hook-less kill | driver step + `probe_kill_group` |
| G6 | plays well | 30 min of human play (see [testing/human-acceptance.md](../testing/human-acceptance.md)) |

G5 is the one teams skip and the one that ruins a session. See
[authoring/anti-softlock.md](anti-softlock.md).
