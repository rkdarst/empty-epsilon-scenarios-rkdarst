# Status page ("where do I go now?")

**Problem.** A mission with three objective lines and a nebula map needs a dialog
the crew can open at any moment of play and get: what is done, what is next, and
what the hints currently say. Written badly, this page is the number one source of
"the dialog lies to me" bug reports.

**Facts.** It is a normal dialog, so the one-message contract and the page/replies
split apply verbatim ([dialog-page.md](dialog-page.md)). `[src]` `[obs]`

## Code

```lua
function commsStatus(t, src)
    local lines = {}
    table.insert(lines, ("Components recovered: %d of %d."):format(delivered_count(), #PART_NAMES))
    for _, name in ipairs(PART_NAMES) do
        local info = parts[name]
        if info and not info.delivered then
            if info.carried then
                table.insert(lines, "- " .. name .. ": in your cargo bay. Bring it to a station.")
            elseif info.obj ~= nil and info.obj:isValid() then
                table.insert(lines, "- " .. name .. ": adrift, last seen near sector "
                    .. (info.drop_sector or "?"))
            else
                table.insert(lines, "- " .. name .. ": unaccounted for. Ask around.")
            end
        end
    end
    table.insert(lines, phase_hint())
    setCommsMessage(table.concat(lines, "\n"))
    commsStatus_replies(t, src)
    return true
end

function commsStatus_replies(t, src)
    addCommsReply("Anything else?", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage(phase_hint())
        commsStatus_replies(t, comms_source or src)
        return true
    end)
    addCommsReply("Close channel.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage("Standing by.")
        return true
    end)
end

function phase_hint()
    if phase == 1 then
        return "Current task: recover the components. Known sites: " .. known_list()
    elseif phase == 2 then
        return "Current task: find the three freighters carrying Ansible Playbooks."
    end
    return "Current task: defend the station."
end
```

Rules this enforces:

* **Never name an unknown location.** `known_list()` only lists stations the crew
  has actually learned about (`known.x = true` is set by the intel dialog) - a
  status page that leaks a hidden site ends the mission early. `[obs]`
* **State comes from the world**, not from a phase string: "in your cargo bay"
  reads `info.carried`, so the page cannot contradict the world.
* **One `setCommsMessage`** - build the text with a table and one concat, so no
  branch can emit twice.
* Put the page on a station *and* on the ship-to-ship page if transfers exist:
  the status page is where a confused crew looks first.

## How to test it

```lua
ee_step(4, function()
    local d = ee_dlg_open(commsStatus, stations.home, active_players()[1])
    ee_check(#d.msgs == 1, "status page renders one message")
    ee_check(d.msgs[1]:find("hidden site name") == nil, "status page leaks no hidden site")
end)
```

That second assertion - "the status page must not contain the name of something
the crew has not learned" - is the highest-value dialog assertion in the whole
suite, because the leak is invisible in play until the mission is broken.

## Variants and pitfalls

* A GM-run session benefits from a `probe_state()`-style line in the page
  (counts only) so a stuck session can be diagnosed from inside the game.
* Keep the page under ~6 lines: the client's dialog box scrolls badly. `[obs]`
* Do not make the status page *do* anything except re-render. Actions belong to
  their own choices ([station-handover.md](station-handover.md)).
