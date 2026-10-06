# 05 — Mission DSL (draft, discussion artifact)

Status: **schema v0.1** (v1 revision of the v0 discussion draft),
demonstrated by [`dsl/samples/last-mile.yaml`](../dsl/samples/last-mile.yaml).
Not executable — codegen is Phase 2. Grammar parsing lives in
`tools/dsl_lang.py` (shared with the future generator); `tools/dsl_check.py`
validates structure, references, the dialog contract, event grammar and
heuristic comms dead-ends.

## Principles (derived from notes 01/04)

1. **Data-only blackboard.** Generated code never stores closures in
   globals (idiom C is a save/load trap — note 04). `flags:` = plain data;
   `fields:` attach to objects (saved with them).
2. **World predicates beat flags where possible** (`alive()`, `has()`,
   distances) — self-healing against GM meddling.
3. **Dialog contract, enforced structurally:** a *page* is text + replies
   only; all side effects live on a *reply*. A reply with `say:` prints
   result text and then the greeting's replies (`then:` overrides). This
   makes the note-01 result-wipe bug unrepresentable.
4. **Name references, not ids.** Names are the authoring identity; stable
   per-entity ids are a GM-editor-phase concern (a GM renaming things must
   not break references).
5. **Conditions are mini-expressions** (`when: "credits >= kajaani.price"`),
   parsed to an AST (today: via Python's `ast` with true/false→True/False).
   Actions are typed command strings (`pay/give/take/set/spawn/hint/gm/
   victory`, optional `if cond:` prefix). Both are compact now and
   de-fangable into an editor registry later.
6. **Engine fixes ride for free:** wormhole pairs get the 3.5U exit offset
   + re-entry guard; every callback gets the `math.abs(0)` upvalue trick;
   `update()` is emitted as the idiom-A loop (timers, stages, outcomes).

## Semantics worth pinning down

- **Stages** are evaluated top→bottom; the *last* matching `when` wins
  (default entry first, upgrades after) — monotonically advancing missions
  read naturally as an ordered list.
- **Events** have exactly one of `after:` (absolute game seconds) or
  `after_flag: {flag, delay}`; the `fire:` mode says whether a false `when`
  at fire time drops the event or retries it (see v1 decisions).
- A reply's visibility is its `when`; hidden replies are not shown, and
  `say`-only replies cover the "menu but no action" case (see `depot`).

## v1 decisions (were v0 open questions)

1. **Strings stay** for `when:`/actions, but the grammar is now normative
   (below) and *implemented once* in `tools/dsl_lang.py`; checker and
   generator must share it — drift is a bug.
2. **Items are honest**: `instance: one_of` + `spawn_as: teleport_object`
   (the LC-proven mechanism). Native `spawnCargo` kinds are a fixed engine
   enum — `spawn_as: cargo` reserved for an EE that has a fitting kind.
3. **`then:` default** = greeting's replies. Kept; `then: {replies: P}` overrides.
4. **Events**: `after:` **or** `after_flag: {flag, delay}` (exactly one);
   `fire: once_when_ready` (default: at delay elapsed, if `when` false the
   event is *dropped*) | `retry_until_true`. Repeating events: still deferred.
5. **Multi-ship crews / jump routes / combat triggers**: deliberately out
   (see "left to Lua" below).

Other v1 changes: `version: 0.1`; `meta.type:` (one of the real header
categories — a missing Type buries the scenario in *Unknown*, note 01);
`meta.api:` pins the vendored EE; entities/archetypes split (`at_start:`);
`n_alive()` for archetype counting; flag `scope:` (`world|ship|player`,
default world); option *values* are vocabulary-checked; `tracker:` must
name a real object (`{object: gate.b}` / `{station: x}` — engine trackers
take SpaceObjects, not systems); `once: <flag>` reply sugar (auto-declared
bookkeeping flag, auto-cleared visibility); dead-end analysis;
`mode: fixed` (v0's `generation` + hand-pinned coordinates was dishonest).

## Generator contract (Phase 2 target)

For dialog `D`, page `P`: emit `D_P(source, target)` → calls `D_P_replies`
which emits one `addCommsReply` per visible reply; `to:` callbacks call
`D_target(...)`, `say:` callbacks run actions, `setCommsMessage(result)`,
then `D_then_replies(...)`. Phases/stages/outcomes compile to one
`update(delta)`; entities become `init()` spawns with name→object tables.
Round-trip acceptance: hand-written equivalent (LC-style) and generated
code must pass the same functional assertions (LC-101-style per section).

## Grammar (normative, v0.1)

Implemented in `tools/dsl_lang.py` (python `ast` as the expression
backend — the Lua codegen translates: `true/false` as-is, `!=`→`~=`,
`none`-style option words → string literals).

**Expressions** (`when:`, `if …:` conditions): `and / or / not`, parens,
comparisons `== != < <= > >=`; names = entity names and `credits` (= the
*talking* ship's credits — ship-scoped by definition); paths
`flags.<f>`, `options.<o>`, `<station>.<field>`; functions
`has(ship, item)`, `alive(object)` (entities only — `alive(archetype)` is
a checker error), `n_alive(archetype) > 0`, `in_range(a, b, m)`,
`distance(a, b)`; `options.X == word` where `word` ∈ that option's values.

**Actions** (strings in `do:`): optional `if <expr>:` prefix, then either
a text action (`gm: hint: message: log: victory: defeat:` + free text) or
a command:

```
set flags.X true|false | set <station>.<field> <value>
give <ship> <item>  |  give <ship> <n> credits  |  take <ship> <item>
pay <number|station.field> to <object>
spawn [n] <archetype> in <system> [at <object>]
warp <ship> to <system>
```

**Entities vs archetypes**: `at_start: true` (default when `position:`
present) = instantiated at init, referenceable by name, `alive()`-able;
`at_start: false` (no position) = archetype, referenced only via `spawn`
and `n_alive()`. After save/load only entities rebind to names;
archetype instances are addressable only in aggregate (note 04).

**Victory precedence**: a `victory:` *action* ends the scenario instantly;
`outcomes.victory.when` is the derived-condition path. Using both at once
is legal but warns.

## Deliberately left to Lua

Two escape hatches, on purpose: (1) the `scripts:` section — raw Lua
verbatim into the generated file (checker only warns it's unchecked);
(2) the project rule: **when the DSL fights a mechanic, hand-write the
scenario.** The DSL targets conventional mission patterns; LC-class
bespoke systems (book-carriers, re-entry guards, ~1900 asteroid belts)
stay hand-written Lua. A mission is a DSL file, a Lua file, or a DSL file
plus `scripts:` — never a strained DSL file.

## Known limitations (v0.1)

- `pay` moves player credits only; station accounts are not modelled
  (checker warns wherever used).
- `options.*` in a page's reply conditions is opaque to the dead-end
  analysis → conservative warnings.
- Only `fixed` layouts; generated-map support deferred.
- The dead-end check is a conservative heuristic over flags × `credits`
  thresholds × `has()` booleans (cap: 6 flags / 4 booleans); beyond the
  cap it warns "cannot prove", never silently passes.

## Verification workflow today

```sh
python3 tools/dsl_check.py dsl/samples/last-mile.yaml   # must print OK
```

PyYAML comes from the system package or, on pip-less hosts, from
`./tools/get_pyyaml.sh` once (rootless sdist extraction into
`vendor/pylibs/`, which the checker finds automatically).
