# API & scripting model

## How the engine loads your file

* A scenario is **one Lua file** named `scenario_<NN>_<name>.lua`; the game
  discovers it with the glob `scenario_*.lua` (upstream `src/scenarioInfo.cpp`).
  There is no registration list. `[src]`
* The **header comment block is parsed before the Lua runs at all**, so a
  missing `Type:` line means the file is filed under *Unknown* ("No scenario
  category" in the log) even though the script itself is fine. Grammar and the
  `Setting[...]`/option-key interaction: [authoring/HEADER-FORMAT.md](../authoring/HEADER-FORMAT.md). `[src]`
* Every `.lua` file in a scanned scripts directory is **concatenated into one
  Lua chunk** (`ScriptClient::load`) and the scenario file is itself one
  anonymous chunk. Consequences you can use:
  - two files in the same directory can see each other's globals (a test driver
    appended after the scenario sees its locals);
  - file-level `local` variables are *not* reachable from another directory's
    file, and `require()` executes in the global environment, where the engine
    registers its own classes — expect name collisions (e.g. a `ShipAI`). `[obs]`
* Content is read from two places: the release's data `scripts/` directory
  (resolved from the binary's CWD) and the fallback content path
  `~/.emptyepsilon/scripts` (`EE_CONF_DIR` overrides). The fallback path can
  *only add* files — it cannot shadow a shipped file by the same name. `[src]`
* `init()` runs once at start; `update(delta)` runs every tick. Everything the
  mission does happens in those two functions or in the callbacks they register. `[ref]`

## The callback contract

Registered callbacks are stored as engine-side function references, which gives
you four rules that are easy to violate:

1. **Define before you register.** `obj:setCommsFunction(my_page)` and friends
   capture the function value at registration time; a later redefinition of
   `my_page` does not update existing registrations. `[src]`
2. **Argument shape varies by callback type.** `ScriptSimpleCallback` (e.g.
   `onCollision`, `setCommsFunction`) is invoked with the *globals table* as
   upvalue #1 and the real arguments as upvalues #2+; `ScriptSerializedFunction`
   (e.g. `onDestruction`, `onPickUp`) is a plain call with `(self, instigator)`.
   A closure written for the wrong shape silently reads nil. The engine's own
   examples start the body with `math.abs(0)` to force the globals-table
   upvalue — copy that idiom when in doubt. `[ref]` `[obs]`
3. **Closures die with the object.** A custom field or closure attached to an
   object is gone once the object is destroyed, so any bookkeeping a hook needs
   must also live in a script-side table that outlives the hull. `[obs]`
4. **Reading a field off a possibly-dead object errors.** Wrap it:
   `local ok, v = pcall(function() return obj.key end)`. `[obs]`

## Comms dialogs

* A comms **function** is documented to receive only `comms_source`; there is no
  `Player.get()`. Bind the target in the closure and fall back to
  `getActivePlayerShips()[1]` when the engine hands you nothing. `[ref]` `[obs]`
* When the engine renders a dialog it **clears all replies, then runs the page
  function / clicked callback**, and *every* `setCommsMessage` inside that call
  **replaces** the previous text. Hence the two rules in
  [patterns/comms.md](../patterns/dialog-page.md): the page function sets text once
  and calls a `_replies` function that only adds choices, and an action callback
  sets its result text and re-adds **choices only**. `[src]` `[obs]`
* `sendCommsMessage(target, text)` returns **false** when that player is busy in
  another dialog — it does not queue. Any "news must arrive" logic needs a queue
  with a retry deadline. `[ref]` `[obs]`
* Player ships are addressable as comms targets (`other:openCommsTo(ship)`), but
  the *player-side* menu to do so is not in 2024.12: ship-to-ship transfer needs
  a ship-side page plus a distance gate in the callback. `[obs]`

## Victory and defeat

`victory(faction_name)` declares the winner and ends the mission; the log shows
`mission complete - victory declared`. There is no "defeat" call — you declare
the enemy faction the winner. `[ref]` `[obs]`

## Logging

* `print(...)` lands in the log prefixed `INFO: LUA:`; engine-side Lua errors
  appear as `ERROR: LUA: <context>: <chunk>:<line>: ...`. Grep both: the smoke
  test's error patterns are exactly these plus the loader's syntax-error form. `[obs]`
* The log is your only test output channel in 2024.12, which is why the harness
  speaks in greppable markers (`EE-ASSERT ok:` / `EE-AUTOTEST done:`).
* `getPreviousScriptError()` does not exist in this build; `pcall` is the only
  error barrier. `[obs]`

## Things that look like API but are not

| You tried | Reality |
|---|---|
| `setBeamDamage()` | no such call; rewrite each arc with `setBeamWeapon(i, arc, dir, range, cycle, damage)` `[obs]` |
| `Player.get()` | absent; use `getActivePlayerShips()` `[obs]` |
| `takeHullDamage()` from a script | engine-side only — a script cannot inflict damage, so it cannot make a hook fire `[obs]` |
| `obj:getName()` | not on `SpaceObject`; ships/stations have `getTypeName()` and `getCallSign()` `[ref]` |
| `getScenarioVariation()` | deprecated alias of `getScenarioSetting("variation")` `[ref]` |
