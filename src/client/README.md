# client/ — StarterPlayer.StarterPlayerScripts.Client

Each `.client.lua` file is a LocalScript that auto-runs on player join.

| Subfolder    | Owner   | Files                                                    |
| ------------ | ------- | -------------------------------------------------------- |
| `UI/`        | OWEN    | `HUD`, `ShopUI`, `TutorialController` — all peripheral UI. |
| `Gameplay/`  | RUBEN | `GlideController` — glide physics + own glide button + distance card. |
| (root)       | JOINT   | `Main.client.lua` — boot log only.                       |

The glide controller draws its own UI alongside its physics. If Owen
needs to restyle that UI, the relevant section is clearly marked at the
top of the file. The HUD, shop, and tutorial UIs are 100% Owen's.
