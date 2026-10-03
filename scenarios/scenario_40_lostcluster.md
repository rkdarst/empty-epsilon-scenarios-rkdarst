# EE Scenario: The lost cluster

## Basics

This scenario is suitable for any number of player ships.

## Scenario script

### Phase 1

(1) It starts in a home station area (Station name: Lumina 1), where there are various patrolling ships near nebula, mines, asteroids, etc.  The station hails you and asks for you to pick up some computing hardware from station Kajaani 1, which is on the other side of the map.

Upon hailing Kajaani 1 (which can happen even when not close to it), they say that they have been looted and the supercomputer is missing  They request help investigating so ask you to come to them.  Once you arrive there, they suggest calling stations LUT 1, Turku 1, Tampere 1.  There are the following parts (despite being plural, each is only one object):

- (A) AMD compute nodes
- (B) Intel compute nodes
- (C) H200 GPU nodes
- (D) B300 GPU nodes
- (E) Lustre fileserver
- (F) Infiniband switches

We can’t see where the others are, but Lumina 1 will give a sector and the station will be within 50u of that point (not exact locations) where they might be and the players have to explore, including inside some nebulas.

When Tampere 1 is hailed from for away, they say they have the H200 GPU nodes.  When approaching Tampere 1, three relative weak enemy ships appear and have to be fought off.  If you try to hail Tampere, they will respond that they are under attack and request that you defeat the ships near it before they talk.  After that, Tampere 1 also will say that the B300 GPU nodes were stolen by some enemy ships that were headed towards sector C10.  If you go to the sector, you can find them.  If you defeat them, they will drop the B300 GPU nodes and you can pick them up.

When approaching station LUT 1, the station suddenly turns into an an enemy station and 3x the current total number of player ships appear.  These ships stay around the station (even as the player ships retreat), and it is expected that the player ships need to group up and attack all together.  If the player ship is alone, the enemy will hail the player ship and taunt them “Alone you are weak and we will be victorious!“.  The taunt happens if only one player ship approaches, and each time only a single player ship approaches.  LUT1 itself appears as hostile but doesn’t attack the player.  The enemy ships nearby don’t leave LUT1 but stay within a sector of it.  Once the ships are gone, station LUT 1 can be hailed and then it will turn friendly again and they will provide the AMD compute nodes.

When approaching station Turku 1, they say that they have been attacked and they have hidden the data in several nearby nebulas, but they ship doing the hiding got destroyed on the way back.  So, you have to go search those nebulas to find the data.  There are seven nebulas randomly placed nearby (same and adjoining sectors) and the Intel compute nodes and Lustre fileservers are randomly hidden in two different of the nebulas.  These components appear as cargo containers or similar and one must scan them to determine the contents.  There are some decoy containers with junk in them.

When someone returns to station Lumina 1 with data segments and hail it, you can give them the objects you found.

### Phase 2

Starts when all components are delivered to Lumina 1.

If all the components are given to station Lumina 1, they will hail all ships and say “Thanks for recovering all the hardware.  However, we have lost our Ansible Playbooks.  We think they have been loaded onto a civilian transport going between our stations.  Can you find them?“  One has to go find all these various transports (say, total of 10 randomly going between stations), aproach and scan them, and hail them, and they will report if they have them.  This will take dividing up and exploring.  There will be easy battles as you find enemy ships in these areas (more ships will be spawned if they are already destroyed).  There are three Ansible Playbooks with names such as “Ansible Playbook 1 (of 3)”.

Once the Ansible Playbooks are found, approach it, pick it up, and bring it back to Lumina 1.

### Phase 3

However, there is a catch!  Once the player ships leave Lumina 1, they get hailed and told a large number of enemies have been detected approaching the station, and players must report back for defense.

## Locations

A1 is at the top left and M20 is at bottom right.  (1-20 goes horizontally)

- Station Lumina 1.  This is the home base and spawn point.  It is around sector E3 and has plenty of supplies for us.  Hailing it will always tell us the latest mission status and what needs to happen next.
- Station Kajaani 1 is around sector H20.  It is friendly and will tell us news even if we are not nearby.
- Station Tampere 1 is around sector H5.  Not visible at the start but Kajaani 1 can tell you where it is.
- Station Turku 1 is around sector B2.  Not visible at the start but Kajaani 1 can tell you where it is.
- Station LUT1 is around sector L3.  Not visible at the start but station Tampere 1 can tell you where it is, but only if you are within 10u of it.  It says this is confidential information.  LUT1 becomes hostile, as if it was a trap and had been taken over by enemies.  The station itself can’t be destroyed and doesn’t fight back, but once the enemies around it are destroyed it gets reverted to friendly control.
- The middle of the map has various friendly and enemy ships, which will attack if we get too close but if we stay away (or run away) they resume their business and don’t follow.

In all areas there is interesting randomly-generated terrain: nebulas, asteroids, mines, other ships and power-ups.  Some sectors are more dense than others.

## Other notes:

- In general, there shouldn’t be a way to completely die or lock the scenario.  If a player ship is destroyed, it should drop its objects and a new player ship can be spawned and resume the scenario.
- Ships carrying objects drop the objects if destroyed.  Dropped objects appear as cargo containers in space.
- To transfer objects, ships or objects must be within 2u and stationary.
- To pick up an object, one has to go close to it and hail it.  One option is “We would like to pick you up.“
- To transfer an object, one has to approach the other ship and hail it.  If it is a non-player ship, it will have an option “Please transfer \[object\] to us“.  If it is a player ship, it will have an option “We would like to transfer \[object\] to you.”
- To turn in an object to Lumina 1, one must hail it and an option will be to hand over the cargo.
- Stations can be hailed from anywhere, if it is visible.  Some are not immediately visible until they are found.
- Friendly stations, civilian ships, and anything required for victory should not be destroyable and enemies will not attack them.
- Non-depending objectives can happen in any order.