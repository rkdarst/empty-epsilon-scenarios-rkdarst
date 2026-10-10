# authoring/ — from an idea to a running mission

| Doc | Read it when |
|---|---|
| [workflow.md](workflow.md) | you want the short loop: brief → outline → skeleton → smoke → driver → play |
| [HEADER-FORMAT.md](HEADER-FORMAT.md) | you are writing or debugging a scenario header (it is parsed before the Lua runs) |
| [from-brief-to-code.md](from-brief-to-code.md) | turning a design brief into an outline and then into the file |
| [brief-guide.md](brief-guide.md) | you are writing the brief itself (facts / feel / flavour / ask) |
| [anti-softlock.md](anti-softlock.md) | before you call a mission finishable |
| [flow-diagrams.md](flow-diagrams.md) | you want the mental model of how the engine runs your file |

## The loop

```
brief            outline              skeleton + patterns           tests/
-----            -------              -------------------           ------
facts/feel/  ->  phases + task    ->  init()/update() +     ->      driver: one step
flavour/ask      graph + knobs        dialogs + probe hooks         per beat, polled
                                                                      assertions
                    ^                              |
                    +---- playtest findings <-------+  (ee-smoke / ee-func / ee-play)
```

The three rules that make it work:

1. **Numbers live in the knob block**, never inside logic
   ([patterns/tuning-knobs.md](../patterns/tuning-knobs.md)).
2. **Every "must happen" has a polled fallback**, because hooks are damage-only
   ([patterns/guanteed-drop.md](../patterns/guanteed-drop.md)).
3. **Every beat gets its assertion before its code**, so a phase cannot silently
   stop being reachable ([testing/writing-drivers.md](../testing/writing-drivers.md)).
