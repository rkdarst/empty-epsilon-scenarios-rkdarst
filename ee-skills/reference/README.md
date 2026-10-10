# Reference — how Empty Epsilon actually behaves

Verified knowledge about **EE-2024.12.08** (what `ee-skills/bin/ee_get.sh`
vendors by default). Each claim carries a provenance tag:

| Tag | Means | How to re-verify |
|---|---|---|
| `[src]` | read in the engine source (`src/**`, upstream `daid/EmptyEpsilon`) | grep the engine tree |
| `[ref]` | stated in `script_reference.html` that ships inside the vendored release | `find vendor -name script_reference.html`, open it |
| `[obs]` | observed in our own headless runs | re-run `ee-smoke.sh` / `ee-func.sh` on the demo scenario |
| `[infer]` | inferred from an observation — **treat as a hypothesis** | test it before building on it |

Rules of thumb:

1. Never argue scenario behaviour from the log alone — log lines can lag the
   world by one tick and `print` of a userdata means nothing. Read the engine
   source, then write a probe (`ee-func.sh` + a driver) to prove it.
2. `[infer]` items are the ones most likely to be wrong for a newer engine
   build. When you bump `EE_TAG`, re-run `ee_selftest.sh`: the demo scenario
   asserts the observable half of everything in here.
3. Anything that only holds for the pinned version should say so. The whole set
   was verified against 2024.12.08; newer PR builds add API (and can change
   radar/AI details), so check the vendored `script_reference.html` first.

| File | Topic |
|---|---|
| [api-and-scripting.md](api-and-scripting.md) | how the engine loads and runs your Lua, the callback contract, pitfalls |
| [runtime-pitfalls.md](runtime-pitfalls.md) | the traps that cost the most debugging time |
| [sensors-and-visibility.md](sensors-and-visibility.md) | what the crew can see, radar layers, nebulae, hiding things |
| [geometry-and-units.md](geometry-and-units.md) | script units vs displayed units, sector grid, station hulls, distances |
| [ai-behaviour.md](ai-behaviour.md) | ship orders, why AI engagements stall, what kills what |
| [sources.md](sources.md) | where answers live (reference, examples, engine source) + grep one-liners |
| [api-quirk-index.md](api-quirk-index.md) | one-liner index: "does X exist / what does X really do" |
