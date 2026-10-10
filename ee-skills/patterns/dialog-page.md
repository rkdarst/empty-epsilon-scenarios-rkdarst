# Dialog page + action split

**Problem.** A player clicks a dialog choice and nothing seems to happen: the
result text is replaced by the page text again, so the click looks dead. The
engine clears all replies, then runs the clicked callback, and **every
`setCommsMessage` inside that callback replaces the current text** - so a
callback that finishes by re-rendering its own page erases its own result. `[src]` `[obs]`

**Facts.** [reference/runtime-pitfalls.md #2](../reference/runtime-pitfalls.md).

## Code

```lua
-- PAGE: sets the text exactly once, then only adds choices.
function commsDepot(t, src)
    setCommsMessage([[Depot. Two cargo cores fell from the hauler east of here.]] ..
        [[ Recover both and bring them back - the transfer gate is physical.]])
    commsDepot_replies(t, src)
    return true
end

-- REPLIES: choices only, never a setCommsMessage of its own.
function commsDepot_replies(t, src)
    addCommsReply("What is out there?", function(comms_source, comms_target)
        math.abs(0)                       -- ScriptSimpleCallback wants globals as upvalue #1
        setCommsMessage([[Waypoint 7, our relay. It went quiet an hour ago.]])
        commsDepot_replies(t, comms_source or src)   -- replies only -> text survives
        return true
    end)
    addCommsReply("Hand over the cores.", function(comms_source, comms_target)
        math.abs(0)
        local ship = src or comms_source  -- the ship that opened the dialog
        setCommsMessage(act_deliver(t, ship))        -- action: returns its result text
        commsDepot_replies(t, comms_source or src)
        return true
    end)
end
```

Attach it through the station helper, which binds the target in the closure - a
comms *function* is documented to receive only `comms_source`, so never rely on
the `comms_target` global. `[ref]` `[obs]`

```lua
s:setCommsFunction(function(src)
    math.abs(0)
    return commsDepot(s, src or comms_source or first_player())
end)
```

**Rules that fall out of the contract:**

* The page function and the `_replies` function are *always* separate functions,
  even for a two-line dialog. It is the only thing that keeps callbacks from
  wiping their own output.
* An action's result must be a single `setCommsMessage` before re-adding choices.
* Conditional pages (`if phase == 2 then ... end`) choose *which* replies to add;
  they must not add two messages.
* `return true` from every page and callback.

## How to test it

```lua
local d = ee_dlg_open(commsDepot, stations.depot, active_players()[1])
ee_check(#d.msgs == 1, "page renders exactly one message")
ee_check(#d.replies >= 2, "page offers its choices")

local msgs = ee_dlg_click(d, 2, stations.depot, active_players()[1])
ee_check(#msgs == 1, "action renders exactly one message")
ee_check(msgs[1]:find("Received") ~= nil, "action took effect")
```

"Exactly one message" is the machine-checkable form of the contract, and it is
the assertion that catches this bug class in every dialog you will ever write.
Also test the *negative* gate (refusal text + no state change) from a location
where the action must be refused - see [station-handover.md](station-handover.md).

## Variants and pitfalls

* **Status page** = one page function that re-renders itself through its own
  `_replies` function; every branch sets text once.
  ([status-page.md](status-page.md))
* **Shop/replenish** pages add a per-item callback that mutates state then calls
  the same `_replies`; never call the page function from the callback.
* **Ship-to-ship** dialogs: there is no player-side "hail another ship" menu in
  2024.12, so put state-changing actions on the *station* page and use the ship
  page only for receiving (`other:openCommsTo(ship)` exists on the object side). `[obs]`
