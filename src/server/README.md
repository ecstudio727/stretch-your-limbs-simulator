# server/ — ServerScriptService.Server

Each service is one module per concern. Subfolders group by ownership
and lifecycle.

| Subfolder       | Owner    | Modules                                     |
| --------------- | -------- | ------------------------------------------- |
| `Data/`         | PARTNER  | `PlayerDataService` — profiles, DataStore, leaderstats. |
| `Progression/`  | PARTNER  | `ShopService`, `RebirthService`, `PetService`, `LeaderboardService`. |
| `Gameplay/`     | PARTNER  | `GlideService`, `CoinService`, `HazardService`, `CheckpointService`. |
| `Onboarding/`   | PARTNER  | `TutorialService` — server-side FSM. |
| `Monetization/` | PARTNER  | (empty — drop game-passes / dev products here). |
| `Map/`          | OWEN     | `MapBuilder` — procedural world build at boot. |

`Main.server.lua` requires every module via the new
`safeRequire(folderName, moduleName)` helper. To add a new service,
drop a `.lua` file into the right folder and add one line to
`Main.server.lua`.
