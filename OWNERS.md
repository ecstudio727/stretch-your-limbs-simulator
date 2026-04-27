# OWNERS

Two-person split. Folders below are tagged so you can avoid editing the
same files in parallel. Anything tagged **JOINT** is a shared interface —
talk before changing.

## Owen — UI, visuals, map design

| Path                                | What's in it                                   |
| ----------------------------------- | ---------------------------------------------- |
| `src/shared/UI.lua`                 | Theme: palette, fonts, sizes, factories.       |
| `src/shared/Config/Map.lua`         | Tree dimensions, phase Y bands, cliff, coin value. |
| `src/server/Map/MapBuilder.lua`     | Procedural world (ground, trunk, four phases, jump branch, atmosphere). |
| `src/client/UI/HUD.client.lua`      | Top-of-screen stats / coins / toasts.          |
| `src/client/UI/ShopUI.client.lua`   | Right-rail buttons + sliding shop / leaderboard / rebirth drawer. |
| `src/client/UI/TutorialController.client.lua` | Objective banner, 3D arrow, highlight, skip button. |

## Partner — gameplay, monetization, everything else

| Path                                              | What's in it                            |
| ------------------------------------------------- | --------------------------------------- |
| `src/shared/Config/Gameplay.lua`                  | Movement, glide math, shop, rebirth, pets, tutorial flow, data, leaderboard. |
| `src/server/Main.server.lua`                      | Boot order, service wiring.             |
| `src/server/Data/PlayerDataService.lua`           | Profiles, DataStore, leaderstats.       |
| `src/server/Progression/ShopService.lua`          | Upgrade purchases.                      |
| `src/server/Progression/RebirthService.lua`       | Rebirth wipe + permanent multiplier.    |
| `src/server/Progression/PetService.lua`           | Pet equip / catalog (gacha/hatching TBD). |
| `src/server/Progression/LeaderboardService.lua`   | OrderedDataStore + top-N cache.         |
| `src/server/Gameplay/GlideService.lua`            | Authoritative glide distance + payout.  |
| `src/server/Gameplay/CoinService.lua`             | Coin pickup / respawn.                  |
| `src/server/Gameplay/HazardService.lua`           | Pendulums, leaves, sap, spore, pads, kill bricks. |
| `src/server/Gameplay/CheckpointService.lua`       | Per-player checkpoint memory + respawn. |
| `src/server/Onboarding/TutorialService.lua`       | Server-side tutorial FSM.               |
| `src/server/Monetization/`                        | Empty — game-passes, dev products, premium boosts. |
| `src/client/Gameplay/GlideController.client.lua`  | Glide physics + glide button + distance card. |

> The glide controller is in `client/Gameplay` because the physics is
> partner-owned, but it also draws its own UI (distance card + GLIDE
> button). If Owen needs to retheme that UI in place it's a small,
> documented section near the top of the file. Coordinate before
> restructuring.

## Joint — change carefully, ping each other

| Path                          | Why it's joint                                        |
| ----------------------------- | ----------------------------------------------------- |
| `src/shared/Remotes.lua`      | Client/server interface contract. Adding remotes is fine; renaming or removing breaks the other side. |
| `src/shared/Util.lua`         | Tiny helpers used everywhere.                         |
| `src/shared/Config/init.lua`  | Re-exports the two sub-configs and hosts helper functions. Don't add data here — add to `Gameplay.lua` or `Map.lua`. |
| `default.project.json`        | Rojo mount points. Only edit when you change the folder layout. |
| `src/server/Main.server.lua`  | Listed under Partner above, but Owen will edit if a new map module needs to be required — small change, just mirror the existing pattern. |
| `src/client/Main.client.lua`  | Boot log only. Either of you can touch.               |

## Workflow tips

1. **Branch per area.** `owen/<thing>` and `partner/<thing>`. As long as
   you each stay in your folders, merges are trivial.
2. **Add, don't rename.** If you want a new tuning, add a key in your
   own Config sub-module — don't relocate someone else's keys.
3. **The Remotes file is the API.** When the partner needs a new
   client→server signal, add it to `Remotes.lua` first, commit, then
   each side wires its half. That's the only file you both touch on
   the same change.
4. **MapBuilder is huge (1,686 lines) but cohesive.** If it starts
   causing merge conflicts, ask the assistant to split it into
   `Map/Phase1.lua` … `Phase4.lua` + `Map/Pieces.lua`.
