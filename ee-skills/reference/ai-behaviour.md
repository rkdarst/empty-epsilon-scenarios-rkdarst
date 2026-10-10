## Ship-order names (there is no `orderMoveTo`)

`CpuShip` orders in 2024.12.08: `orderIdle`, `orderFlyTowards`,
`orderFlyTowardsBlind`, `orderFlyFormation`, `orderRoaming`, `orderRoamingAt`,
`orderStandGround`, `orderDefendLocation`, `orderDefendTarget`, `orderDock`,
`orderRetreat`, `orderAttack`. Commonly-hallucinated names that do **not** exist:
`orderMoveTo`, `orderPatrol`, `orderFollow`, `orderEscort`. `[ref]` `[obs]`

## AI engagement: an idle target is a safe target

A Starhammer II squad ordered to attack a **stationary** (`orderIdle`) ship
closes to ~11u, parks there and never fires - hull unchanged for 90+ s while the
merc dump shows it sitting at 1.3-4.4u from the target after a drop-in. Order the
same target to *move* (`orderFlyTowards`) and the AI chases and kills it. `[obs]`

Two consequences:

* Scenario: an "escort" you expect to die should be moving; a parked patrol is
  effectively invulnerable to AI attackers, which also makes it a good way to
  build a durable roadblock.
* Tests: an organic-kill assertion against idle targets is a flaky assertion.
  Give the target flight orders, and keep the driver's anti-camping logic (one
  clean drop-in per ~45 s, never teleport spam) as the backstop. See
  [testing/writing-drivers.md](../testing/writing-drivers.md).

The Starhammer II AI fires only HVLI tubes (`ShipAI::runAttack` does not fire
beams), so its kills depend on tube hits at closing range - which is exactly why
a non-moving target with a small radar cross-section is never engaged. `[src]` `[obs]`
