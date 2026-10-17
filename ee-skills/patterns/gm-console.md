# Gamemaster console (paged GM controls)

**Problem.** A human runs the table and needs levers: "hand them the crate",
"start the finale", "what is the current state?" — without editing Lua mid-game
and without a pile of `probe_*` hooks that only a test driver can call.

**Facts.** The whole scripting surface for the GM console is six functions, and
none of them is a menu:

| Call | What it really is |
|---|---|
| `addGMFunction(name, cb)` | one button, `name` is its label `[ref]` |
| `removeGMFunction(name)` / `clearGMFunctions()` | take buttons away `[ref]` |
| `addGMMessage(msg)` | a dismissable popup on the GM's screen `[ref]` |
| `getGMSelection()` | the objects the GM selected; `[]` when nothing is selected `[ref]` `[obs]` |
| `onGMClick(cb)` | click on the console background, gets game coordinates; works from a scenario script, not the HTTP API `[ref]` |

From those facts come the five rules this pattern exists to encode:

1. **There is no nesting.** Shipped missions fake a tree with a label
   convention - `+Label` opens a page, `-Label` goes back - and swap pages by
   hand: `clearGMFunctions()` then re-add.
   (`vendor/.../scripts/scenario_88_chaos.lua`) `[src]`
2. **The list belongs to the script, not to a GM.** Nothing in the API takes a
   player argument, so two GMs share one list: whoever renders last owns the
   screen. Re-render the page after *every* action so nobody is left staring at
   dead buttons. `[ref]`
3. **A callback must have the globals table as upvalue #1.** Passing a named
   function that references a chunk local fails at registration with
   `??[convert<ScriptSimpleCallback>::param] Upvalue 1 of function is not a
   table`; closures whose first statement is `math.abs(0)` always work. `[obs]`
4. **Headless, the API is inert but safe.** `addGMFunction` / `clearGMFunctions`
   / `addGMMessage` succeed, `getGMSelection()` returns an empty table, and
   buttons register from `init()` and from `update()` alike - so pages render in
   the autotest, they just cannot be *clicked*. The console is plain Lua too:
   this build has no `callscriptfunction()`, so a console line *is* a script
   call (`lc_gm_status()`), while a headless stdin line is ignored by the
   engine. `[obs]`
5. **A label has about 20 characters, and the cell centers it.** The button is a
   fixed-width cell, so text past the width is cut at *both* ends and what
   disappears is the verb: "Drop every missing crate nearby" reads as
   "...missing crate...". Budget 20 characters, verb first, and move anything
   longer into `addGMMessage` (a popup has no width problem) or into a
   one-character state marker. `[obs]`

So: a page is a function that adds its buttons; state that does not fit goes in
the message; and the label length is enforced in code, because a clipped label is
invisible to every test that is not looking at it.

## Code

The plumbing: one button helper that satisfies rule 3, one log line per action
(the console has no text fields, so the log is the observable truth), and a
pager that owns rule 2.

```lua
LC_GM_MENU = getScenarioSetting("GMMenu")           -- Enabled|Disabled
if LC_GM_MENU == nil or LC_GM_MENU == "" then LC_GM_MENU = "Enabled" end
lc_gm_page, lc_gm_arg = "main", nil
lc_gm_hidden = (LC_GM_MENU == "Disabled")

function lc_gm_log(msg)
    LC_GM_CALLS = (LC_GM_CALLS or 0) + 1            -- audit counters the driver
    lc_gm_last = msg                                -- can assert on
    print("LC-GM: " .. msg)
    return msg
end

function lc_gm_say(msg)                             -- log line + GM popup
    lc_gm_log(msg)
    pcall(addGMMessage, "LC: " .. msg)
    return msg
end

function lc_gm_guard()                              -- nothing works after "done"
    if done then
        lc_gm_say("mission already finished - controls are locked")
        return false
    end
    return true
end

-- Rule 5: one place where a label becomes something the cell can show.
LC_GM_LABEL_MAX, LC_GM_LABEL_OVER, LC_GM_LABEL_LONGEST = 20, 0, 0
lc_gm_label_longest_text = ""

function lc_gm_label(label)
    label = tostring(label)
    if #label > LC_GM_LABEL_LONGEST then
        LC_GM_LABEL_LONGEST, lc_gm_label_longest_text = #label, label
    end
    if #label <= LC_GM_LABEL_MAX then return label end
    LC_GM_LABEL_OVER = LC_GM_LABEL_OVER + 1        -- the driver asserts this is 0
    print("LC-GM: label over the " .. LC_GM_LABEL_MAX .. "-char budget (" .. #label .. "): " .. label)
    return label:sub(1, LC_GM_LABEL_MAX - 3) .. "..."
end

-- Progress without a ": delivered" suffix: the dive marker carries it.
function lc_gm_done(name)
    local info = parts[name]
    return (info ~= nil and info.delivered == true) and "*" or "+"
end

function lc_gm_button(label, fn)
    LC_GM_BUTTONS = (LC_GM_BUTTONS or 0) + 1
    local shown = lc_gm_label(label)
    local ok, err = pcall(addGMFunction, shown, function()
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        return fn()
    end)
    if ok == false then print("LC-GM: addGMFunction(" .. shown .. ") failed: " .. tostring(err)) end
    return ok
end

function lc_gm_open(page, arg)
    lc_gm_page, lc_gm_arg = page, arg
    lc_gm_render()
end

function lc_gm_back(page)
    lc_gm_button("-Back", function() lc_gm_open(page) end)
end

lc_gm_pages = { main = lc_gm_page_main, parts = lc_gm_page_parts }  -- name -> page fn

function lc_gm_render()
    local before = LC_GM_BUTTONS or 0
    pcall(clearGMFunctions)
    if lc_gm_hidden then
        lc_gm_button("+Lost Cluster menu (hidden)", function() lc_gm_menu(true) end)
    else
        (lc_gm_pages[lc_gm_page] or lc_gm_pages.main)()
    end
    print("LC-GM: page " .. lc_gm_page .. " drawn, " ..
        ((LC_GM_BUTTONS or 0) - before) .. " button(s)")
end

function init()
    -- ... world building ...
    pcall(lc_gm_boot)      -- a missing GM API must never break a mission
end
```

A page is a function that adds buttons; the label carries live state so the GM
can read the situation without opening anything:

```lua
function lc_gm_page_main()
    lc_gm_button("= Lost Cluster, phase " .. phase .. " =", function() lc_gm_open("main") end)
    lc_gm_button("+Cluster components (" .. part_delivered_count(PART_NAMES) .. "/6)",
        function() lc_gm_open("parts") end)
    lc_gm_button("Status report", function() lc_gm_status() end)
end
```

And an action. Three conventions make these safe to hand to a human: it is
**guarded** (nothing works after the mission ends), **idempotent** (pressing it
twice says "already done" instead of doubling the world), and it changes the
world through the **same functions the mission itself uses** - a shortcut that
skips the mission's own consequence code is how a GM arms a phase the players
never reached:

```lua
function lc_gm_mark_part(arg)
    if not lc_gm_guard() then return "locked" end
    local phase_before, n, skipped = phase, 0, 0
    for _, name in ipairs(lc_gm_part_names(arg)) do      -- "all", exact name, or index
        local info = parts[name]
        if info == nil then
            parts[name] = { carried = false, delivered = false }
            info = parts[name]
        end
        if info.delivered then
            skipped = skipped + 1
        else
            lc_gm_uncarry(name)                          -- out of whatever cargo bay
            lc_gm_clear_crate(name)                      -- and no duplicate crate
            info.delivered = true
            n = n + 1
        end
    end
    local extra = lc_after_delivery()                    -- the mission's own path
    return lc_gm_say("marked " .. n .. " part(s) delivered, " .. skipped ..
        " already done" .. extra)
end
```

Because the globals are the doorway, the same controls work as buttons *and* as
console commands: a GM at the host can type `lc_gm_phase2()` in the LUA console,
and the driver calls the same function. Ship the list in the scenario so nobody
has to remember it:

```lua
function lc_gm_help()
    return lc_gm_report("console commands (each line is Lua on the server):\n" ..
        "  lc_gm_status()   lc_gm_mark_part(\"all\")   lc_gm_phase2()   lc_gm_sweep(\"wave\")")
end
```

## How to test it

Buttons cannot be clicked headless, so the driver drives the globals - which is
exactly the point of making the buttons wrappers. From
[tests/scenario_40_lostcluster.autotest.lua](../../tests/scenario_40_lostcluster.autotest.lua):

```lua
table.insert(steps, { t = 6.0, f = function()
    lc_check(type(lc_gm_pages) == "table" and next(lc_gm_pages) ~= nil,
        "the pager's page table is built whatever the menu setting says")
    if LC_GM_MENU == "Disabled" then            -- this run tests the hidden path
        lc_check(gm_redraw("main") == 1, "a hidden menu draws only the un-hide button")
        lc_gm_menu(true)                        -- what that button does
        lc_check(lc_gm_hidden == false and gm_redraw("main") > 1,
            "and one click brings the whole menu back")
    else
        local buttons_before = LC_GM_BUTTONS or 0
        local bad, n = lc_gm_pages_sweep()      -- lc_gm_show(name) for every page
        lc_check(#bad == 0, "all " .. n .. " GM pages render headless")
        lc_check((LC_GM_BUTTONS or 0) > buttons_before, "rendering registers buttons")
        -- Rule 5, made measurable: the sweep opened every page *and* every detail
        -- page for every subject, so a label built from a data string was rendered
        -- at its longest and had nowhere to hide.
        lc_check(LC_GM_LABEL_OVER == 0, "every label fits the " .. LC_GM_LABEL_MAX
            .. "-char cell (longest " .. LC_GM_LABEL_LONGEST .. ")")
        lc_check(lc_gm_done(PART_NAMES[1]) == "+", "an open subject carries '+'")
    end
end })
```

`gm_redraw` measures the *delta* of the cumulative button counter - the engine's
list is cleared on every page swap, so an absolute count asserts nothing. Keep
the two branches in one step: the same driver then proves both settings work, and
neither branch can rot unnoticed.

Every action then gets its own step, asserting the *world*, not the log:

```lua
table.insert(steps, { t = 6.4, f = function()
    local before = found.lut
    lc_gm_reveal_station("all")
    lc_check(before == false and found.lut == true, "GM reveal makes LUT 1 a known contact")
    lc_check(known.lut ~= true, "revealing is not the same as knowing the coordinates")
end })
```

What to demand of any GM action, and how:

| Assert | Why |
|---|---|
| every page renders (`lc_gm_show(name) ~= false`) | a page that throws leaves a blank console and no error on screen |
| the button counter grew | registration really happened, not merely "no error" |
| the effect shows in world state, not only in the log | an action that only prints is a broken button |
| calling it twice says "0 …/already" | a GM double-click must not double the world |
| it returns `"locked"` once `done` is set | the finale cannot be re-armed during the debrief |
| `LC-GM:` audit lines are in the log | the log is the only thing the run leaves behind |
| the hidden path (one un-hide button, then a full page) | `Setting[GMMenu]` is a real branch, and a driver that only tests `Enabled` leaves it untested |
| `LC_GM_LABEL_OVER == 0` after a full sweep | a clipped label is invisible to every test that is not looking at it, and to the GM until they need the verb |

Testing the lock needs a finished mission; flip the flag for one step instead of
playing to the ending (the runner stops 3 s after the first `done` line, so the
real ending is not available to a later step):

```lua
local saved = done
done = true
local r1 = lc_gm_mark_part("all")
done = saved
lc_check(r1 == "locked", "GM actions refuse to run once the mission is over")
```

## Variants and pitfalls

* **Never hand `addGMFunction` a named function** that touches a chunk local -
  it fails at registration `[obs]`. Route everything through the button helper.
* **Never `destroy()` a ship in an action.** `onDestruction` is damage-only, so a
  removed patrol drops no crate and the mission becomes unsolvable
  ([runtime-pitfalls.md #1](../reference/runtime-pitfalls.md)). Wipes use
  `takeDamage(5000, "hull")`; artifacts are the one object where `destroy()` is
  right, because their bookkeeping lives in the script. `[obs]`
* **Do not keep state in the button list.** It is the GM's screen, not the
  mission's: another GM, or a re-render from another callback, can replace it at
  any time. Anything a page needs must live in scenario state (`lc_gm_page` plus
  `lc_gm_arg`).
* **Selection is optional.** `getGMSelection()` is empty when nothing is selected
  *and* in every headless run, so each action needs a sensible fallback ("the
  first freighter without a booking", "next to the players").
* **The labels that overflow are the dynamic ones.** `"+Part " .. name .. ": " ..
  state` looked fine at authoring time and reaches the cell at 40 characters once
  the data is loaded. Budget it in the button helper, and have the sweep render
  every detail page for *every* subject so the longest string is the one measured.
  `[obs]`
* **`Setting[GMMenu]` plus a hide button, not a second code path.** A table that
  wants no menu sets `lc_gm_hidden`, and the render then draws exactly one button
  - the one that brings the menu back - instead of the page. The actions stay
  callable from the console either way, which is what makes defaulting the
  setting to `Enabled` safe, and it means a `GMMenu=Disabled` run is still a test
  of the actions rather than a boot-only smoke. `[obs]`
* Swapping the page from inside a callback is the normal case, not a special one:
  the engine rebuilds the list for the next frame, so `lc_gm_open()` from a button
  is how every page transition works. `[obs]`
* Live labels ("(4/6)") only refresh when something re-renders, which is why every
  action ends in a re-render. A GM who leaves a page open during a fifteen-minute
  firefight sees stale numbers - accept that, or give the page a "Status report"
  button whose only job is to redraw.
