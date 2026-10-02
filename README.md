# sando

Roblox 1v1 melee PvP game. You queue from a lobby, get matched into an arena, and fight rounds using attacks, parries, dodges and a charged ultimate. There are no special powers. Everyone starts with a free Katana, and you unlock other weapons like daggers, Naginata and Warhammer with gold earned from duels. There are Casual, Ranked and 2v2 queues.

Everything, including the map, is generated in code when the server starts, so the project needs no Studio assets.

## Play it now

1. Download [`build/sando.rbxl`](build/sando.rbxl) and open it in Roblox Studio.
2. Press **Play** to try the lobby, shop and training dummies by yourself.
3. To test a real duel, open the **Test** tab, set Clients to **2**, then click **Start**. Both players walk onto the **1v1 Duel** pad (or click it in the Play menu).

To save progress in Studio, publish the place, then turn on **Game Settings → Security → Enable Studio Access to API Services**. Without that, gold and wins only last for the session.

## Controls

| Action | Keyboard / mouse | Gamepad | Mobile |
| --- | --- | --- | --- |
| Light attack (combo) | Click | R2 | Attack button |
| Heavy attack | Hold **E**, release to swing | L2 | Heavy button |
| Parry | **F** | R1 | Parry button |
| Dodge | **Q** (moves the way you're walking, or back) | B | Dodge button |
| Ultimate | **G** when the meter is full | Y | Ult button |

Shift lock is on, which makes aiming easier.

## How combat works

- **Light attacks** chain into a combo. The last hit hits harder but leaves you open longer.
- **Heavy attacks** charge while you hold. When your weapon glows red, the charge is past 85% and **can't be parried**, but you can still dodge it.
- **Parry** has a 0.25s window. Parry a hit and the attacker is stunned for 1s, so punish them.
- **Dodge** gives 0.3s of invincibility. It has a cooldown, so don't waste it.
- **Ultimate** fills as you deal damage, take damage and land parries. It hits a wide area and can't be parried.
- Any hit cancels whatever the victim was winding up.

All timing, hit detection and damage are checked on the server. Clients only send button presses.

## The map

- **Lobby:** a spawn plaza with a torii gate, three queue pads (1v1 Duel, Ranked 1v1, 2v2 Clash), the **Armory** (walk up to a pedestal to buy or equip a weapon), a **training yard** with dummies, and a controls board.
- **Arenas:** four arenas built far from the lobby. **Dojo Courtyard**, **Bamboo Grove**, **Volcanic Rim** and **Frozen Shrine** are each themed with their own props and lighting. Each match grabs a free one at random.

## Modes

| Mode | Players | Format | Unlocks after | Win / loss gold |
| --- | --- | --- | --- | --- |
| 1v1 Duel | 2 | Best of 3 | Always open | 100 / 25 |
| Ranked 1v1 | 2 | Best of 5, Elo | 10 duels | 150 / 30 |
| 2v2 Clash | 4 | Best of 3 | 3 duels | 120 / 30 |

Rounds last 90s. If time runs out, the team with more health left wins the round.

## Weapons

| Weapon | Price | Style |
| --- | --- | --- |
| Katana | Free | Balanced |
| Dual Daggers | 300 | Fast 4-hit combos, short reach |
| Gauntlets | 400 | Fastest, tiny range |
| Bo Staff | 450 | Wide sweeping arc |
| Naginata | 600 | Longest reach, slower |
| Warhammer | 900 | Slow, huge damage |

Damage, speed, range and the model of each weapon live in [`src/shared/Weapons.luau`](src/shared/Weapons.luau). To add a weapon, add one entry there and it shows up in the Armory automatically.

## Developing

The project uses [Rojo](https://rojo.space) so the code lives in files instead of inside a place.

```sh
rokit install                    # or: aftman install (installs Rojo 7.7.0)
rojo serve                       # live-sync into Studio with the Rojo plugin
rojo build -o build/sando.rbxl   # rebuild the place file
```

| Path | What it does |
| --- | --- |
| `src/server/init.server.luau` | Entry point: builds the map, starts services, spawns players |
| `src/server/MapBuilder.luau` | Lighting, lobby, armory, dummies and the four arenas |
| `src/server/CombatService.luau` | Attacks, parries, dodges, ultimates, damage |
| `src/server/MatchService.luau` | Rounds, scoring, rewards and Elo |
| `src/server/QueueService.luau` | Matchmaking queues and the lobby pads |
| `src/server/DataService.luau` | Saves gold, wins, Elo and weapons with DataStores |
| `src/shared/Config.luau` | All tuning numbers (timings, damage gain, rewards, modes) |
| `src/shared/Weapons.luau` | Weapon stats and models |
| `src/client/CombatController.luau` | Input for keyboard, gamepad and touch; dodge movement |
| `src/client/Effects.luau` | Swing animations, trails, sparks, damage numbers, screen shake |
| `src/client/Hud.luau` | Play menu, scoreboard, health bars, ultimate meter, toasts |

Swings are animated by rotating the weapon in the hand, so the game works with no animation assets. If you make real animations in Studio, play them from `Effects.luau` when a `Swing` event arrives.
