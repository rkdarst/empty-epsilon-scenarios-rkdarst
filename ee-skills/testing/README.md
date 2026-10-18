# testing/ — how a scenario is proven to work

| Doc | Read it when |
|---|---|
| [runner-anatomy.md](runner-anatomy.md) | you want to know what the runner actually executes (chunk assembly, throwaway HOME, port guard, error and end markers, env knobs) |
| [writing-drivers.md](writing-drivers.md) | you are writing or extending a driver in `tests/` |
| [communication-testing.md](communication-testing.md) | you want to assert what the crew was *told* — push/persist/pull channels, descriptions, idle hints (spies, choke points, click-by-label) |
| [runtime-surprises.md](runtime-surprises.md) | a run is green but something feels wrong, or a test passes that shouldn't |
| [human-acceptance.md](human-acceptance.md) | the suite is green and it's time to actually play it |

## The pyramid, in one place

```
ee_smoke.sh    boot + init + a few ticks          ~25 s     every edit
ee_func.sh     full mission, ~30-130 assertions   1-4 min   every commit
30-min session client-side feel, UX, visibility    human     before shipping
```

Rule of thumb: if a bug was found by hand, it becomes an assertion in a driver;
if a bug cannot be found headless at all, it goes on the human-acceptance list.

## What the tools are

`ee-smoke`/`ee-func` (in [../bin/](../bin/), wrapped by `tools/*.sh`) boot the real
game headless against a throwaway config directory. A driver is *concatenated into
the same Lua chunk* as the scenario, which is why it can call the scenario's own
functions and why drivers must not sit in `scenarios/`.
