# Stretch Your Limbs Simulator

Roblox game skeleton managed with [Rojo](https://rojo.space). Climb a giant tree obby, leap from the top branch, and stretch your limbs into wings to glide as far as you can.

## Project layout

```
default.project.json      # Rojo project definition
src/
  shared/                 -> ReplicatedStorage.Shared
    Config.lua            # all tuning values
    Remotes.lua           # creates & returns RemoteEvents/Functions
    Util.lua              # small helpers
  server/                 -> ServerScriptService.Server
    Main.server.lua       # entry point, wires services together
    MapBuilder.lua        # procedurally builds tree + obby + jump branch
    PlayerDataService.lua # DataStore persistence, leaderstats, per-player profile
    GlideService.lua      # measures glide distance, awards coins
    CoinService.lua       # binds coin pickups on the obby
    ShopService.lua       # handles upgrade purchases
    RebirthService.lua    # wipes progress, grants permanent multiplier
    PetService.lua        # pet equip skeleton
    LeaderboardService.lua# OrderedDataStore for top glide distances
  client/                 -> StarterPlayer.StarterPlayerScripts.Client
    Main.client.lua       # boot log
    GlideController.client.lua # space/E to glide, stretches arms
    HUD.client.lua        # coins / rebirths / best glide display
    ShopUI.client.lua     # upgrades, rebirth, leaderboard panel
```

## Setup

1. **Install Rojo** (one-time):

   ```bash
   # with Aftman (recommended)
   aftman install rojo-rbx/rojo@7.4.1

   # or with Foreman / cargo / the VS Code extension
   ```

2. **Install the Rojo plugin in Roblox Studio** so Studio can connect to the local server.

3. **Serve this project:** open a terminal *inside* this folder (the one containing `default.project.json`) and run:

   ```bash
   rojo serve
   ```

   Rojo will print a port (default `34872`). If you get "path not found," you're in the wrong directory — `cd` into the folder that has `default.project.json` first.

4. **Connect from Studio:** open a new baseplate, click the Rojo plugin icon, click **Connect**, keep the default host/port. Studio syncs the `src/` tree into the DataModel.

5. **Run the game:** press F5 (Play Solo) or Play. `Main.server.lua` will build the tree and start every service. The Rojo plugin will continue live-syncing changes you make on disk.

## Publishing

Rojo's `rojo build` can produce a `.rbxl` / `.rbxlx`:

```bash
rojo build -o StretchYourLimbs.rbxlx
```

Open the resulting file in Studio and use **File -> Publish to Roblox As...** to push it to your Roblox place, or use `rojo upload` with an API key.

## Game loop

1. Player spawns on the pad next to the tree.
2. They climb spiraling wooden platforms up the trunk. Colored neon platforms are checkpoints. Coins sit along the path.
3. At the top, they walk onto the long jump branch.
4. While airborne from that height, pressing **Space** or **E** triggers glide mode: limbs stretch outward, fall speed drops, forward velocity kicks in.
5. When they land, horizontal distance -> coins. New records are posted to the global leaderboard.
6. Back on the ground, they spend coins in the shop (wingspan, jump power, walk speed) and eventually rebirth for a permanent coin multiplier.

## Tuning knobs

Everything gameplay-facing lives in `src/shared/Config.lua`:

- `Config.Glide` – fall speed, forward speed, coin reward rate
- `Config.Map` – tree size, spiral count, coin count
- `Config.Shop` – max levels, base costs, growth curves, per-level effects
- `Config.Rebirth` – requirements, multiplier per rebirth
- `Config.Pets` – catalog (starter pet `Leaf` is granted on first join)

## Known skeleton-level TODOs

- Pet models that physically follow the player
- Pet hatching / egg gacha flow
- VFX for coin pickup + glide trails
- Sound effects
- Mobile touch controls for glide activation (currently keyboard-only)
- Better anti-cheat on glide distance (current check is loose)
- Actual tree art — the current trunk is a single cylinder for speed of iteration

It's rough, but it's playable end to end.
