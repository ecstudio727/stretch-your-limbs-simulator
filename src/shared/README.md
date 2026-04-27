# shared/ — ReplicatedStorage.Shared

Both client and server require these modules. Treat as the public API.

| File                  | Owner    | Purpose                                  |
| --------------------- | -------- | ---------------------------------------- |
| `Config/init.lua`     | JOINT    | Merges Gameplay + Map; helper functions. |
| `Config/Gameplay.lua` | RUBEN  | Movement, glide, shop, rebirth, pets, data, tutorial, leaderboard. |
| `Config/Map.lua`      | OWEN     | Tree, phases, cliff, coin value.         |
| `Remotes.lua`         | JOINT    | RemoteEvent / RemoteFunction definitions. |
| `Util.lua`            | JOINT    | Small helpers (deepCopy, formatNumber, horizontalDistance). |
| `UI.lua`              | OWEN     | Palette, fonts, sizes, GUI factories.    |

`Config` is a folder ModuleScript — `require(Shared:WaitForChild("Config"))`
returns the merged table just like before, so existing call sites
(`Config.Glide.X`, `Config.Map.X`, `Config.getGlideParams(...)`) keep
working.
