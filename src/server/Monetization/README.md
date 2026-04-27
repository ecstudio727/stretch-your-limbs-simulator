# server/Monetization/

Empty. Reserved for monetization services — game passes, developer
products, premium-only boosts, daily-reward streaks, etc.

When you add a module here, register it from `Main.server.lua` with:

```lua
local MyService = safeRequire("Monetization", "MyService")
if MyService and PlayerDataService then
    safeCall("My", function() MyService.init({ PlayerDataService = PlayerDataService }) end)
end
```

The dependency-injection pattern (passing `PlayerDataService` and any
others through `init(deps)`) keeps these services swappable and easy to
test in isolation.
