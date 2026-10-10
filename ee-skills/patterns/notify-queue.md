# Notification queue

**Problem.** The mission has news ("the freighter was lost, its playbook is
adrift near sector F8") and the crew must hear it - but
`sender:sendCommsMessage(player, text)` **returns false and drops the message**
when that player is currently inside another dialog. `[ref]` `[obs]`

## Code

```lua
msgq = {}

function notify(msg, from)                    -- from = station object (voice)
    table.insert(msgq, { msg = msg, from = from, until_s = clock + 25, done = {} })
end

function pump_messages()
    if #msgq == 0 then return end
    local players = active_players()
    for i = #msgq, 1, -1 do
        local q = msgq[i]
        local sender = q.from
        if sender == nil or not sender:isValid() then sender = stations.home end
        local waiting = false
        for _, p in ipairs(players) do
            local key = p:getCallSign()
            if key == nil or key == "" then key = tostring(p) end
            if not q.done[key] then
                if sender:sendCommsMessage(p, q.msg) then
                    q.done[key] = true
                else
                    waiting = true                       -- busy: retry next tick
                end
            end
        end
        if not waiting or clock > q.until_s then table.remove(msgq, i) end
    end
end
```

Call `pump_messages()` from `update()`. Three details that matter:

* **Per-recipient done-set** keyed by call sign: a 4-player crew should not
  re-receive a message three times because one member was busy. `[obs]`
* **A deadline** (`until_s`), otherwise a player who stays in a dialog keeps the
  queue growing.
* **A fallback sender**: station objects die, and `notify` is often called from a
  hook whose `from` object is exactly the wreck.

## Variants

* `broadcast(msg)` = `notify(msg, nil)` (always the home station's voice).
* A "priority" line can jump the queue; do not add it until a real mission needs
  it - the retry loop already guarantees eventual delivery within the deadline.
* If the same news must be visible *inside* a dialog as well, add it to the status
  page text ([status-page.md](status-page.md)) rather than sending twice.

## How to test it

```lua
ee_step(6, function()
    notify("queued while nobody is free", stations.home)
    ee_until("queue drains once the crew is idle", 5, function() return #msgq == 0 end)
end)
```

Headless has an idle player hull, so delivery succeeds immediately and `#msgq`
drops on the next tick. To test the *retry* path you need a busy recipient, which
is a client-side state - so assert the queue's shape instead: a message that
fails to send must still be in `msgq` with `until_s` in the future. `[obs]`

## Pitfalls

* Do not call `sendCommsMessage` directly from a hook "just this once" - the hook
  often runs at the exact moment the crew opened the dialog that killed the ship.
* `sendCommsMessageNoLog` exists for flavour lines you don't want in the
  messages tab; keep it out of the queue so mission-critical text stays logged. `[ref]`
