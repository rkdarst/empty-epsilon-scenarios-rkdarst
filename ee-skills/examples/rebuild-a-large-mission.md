# Rebuilding a large mission (1000+ lines) safely

A worked method for growing or rewriting a big scenario without losing a working
baseline. It comes from rebuilding a ~1900-line mission phase by phase under
assertion coverage; the numbers are from that run.

## Principle: one invariant per beat, added before the code

A "beat" is one player-visible behaviour ("the relay reveals itself when you
arrive"). For each beat:

1. write the assertion first (a step in the driver),
2. implement the beat,
3. run the driver,
4. commit only when the whole suite is green.

The reason it must be the *assertion* first: a large mission's failure modes are
invisible in the log ("the crate exists" looks fine even when it is inside a hull
nobody can reach).

## The ladder

| Phase | Scope | Typical driver steps |
|---|---|---|
| P0 | boot + world census (counts, factions, no overlaps) | 4-6 at t=2 |
| P1 | first beat end to end, including its dialog | 3-5 |
| P2 | each remaining beat, one per step group | 3-5 per beat |
| P3 | anti-softlock: hook-less kills, respawn, long idle | 3-6 |
| P4 | final invariants + difficulty settings | 2-4, × settings |

Each phase ends with a green `ee_func.sh` run and a human sanity check of the log
(not just the exit code: read the `probe_state()` lines).

## Sequencing rules that saved the rebuild

* **Never move two phases at once.** A phase move + a knob retune is two
  variables and the driver cannot tell you which broke it.
* **Keep the twin.** When translating a phase to a new structure (in our case, to
  a DSL), keep the old phase running behind a flag until the new one reproduces
  every assertion. Ours ran side by side for the whole rebuild; the twin's driver
  is still in `tests/`.
* **Geometry assertions beat logic assertions.** `ee_eject_clear`, "no two
  objects within 0.4u", "no station inside a nebula" catch the class of bug that
  makes a mission unwinnable and that no logic test will see.
* **Poll deadlines are knobs.** Tie each `ee_until` deadline to the scenario knob
  it depends on (`SC.respawn_s + 20`), so a retune updates the test for free.
* **Budget the AI kills.** Organic kills are the slow part: ~20-45 s each. A
  mission with five organic-kill beats has a ~4-minute test. Keep one of them
  behind a `-quick` selection if the suite gets painful, but never delete one:
  it is the only thing proving the hooks actually fire.

## Log-reading discipline

```sh
grep -aE "ERROR|ASSERT FAIL" /path/to/ee.log            # what broke
grep -a  "probe_state\|seeded\|watchdog" ee.log          # what the world thinks
grep -ac "ASSERT ok" ee.log                             # coverage actually ran
```

Three cheap smells worth grepping on every long run: `ERROR: LUA` (tick-abort
loops), the same line repeated >100 times (a poll that spams), and a respawn line
appearing more often than `respawns_left` allows (the conveyor bug).

## When it goes wrong

| Symptom | First thing to check |
|---|---|
| suite passes, play is broken | you asserted your model, not the world — add a geometry assertion |
| suite fails, play is fine | a sampled condition — convert it to a poll with a deadline |
| fails only in CI / headless | something needs a client (movement, collision pickup) |
| passes headless, fails in the client | faction/visibility or dialog rendering; see [testing/human-acceptance.md](../testing/human-acceptance.md) |
| slower every rebuild | the census line: nebula/object counts crept up |
