# Halo

Radial menus for WoW Forever: hold a key, point at a slice, let go to use it.

## Install

Put the `Halo` folder in `World of Warcraft\_forever_\Interface\AddOns\`.

## Use

- `/halo` opens the window. Starter rings: Supplies, Travel, Emotes.
- **New ring**, then set a **Key** or **Gamepad** button.
- Drop spells, items, mounts, toys, pets or macros on the ring. **+** adds emotes, markers, lists, other rings, macros.
- Drag a slice to move it. Right-click removes it.
- A ring holds 12 slices. Automatic lists fill what is left.
- Gamepad layers: give a ring R3, another R3 + L1. Hold L1 in the R3 ring to switch.
- Gamepad bar combos (R1 + D-pad): **...** → **Make macro**, put it on that slot.
- Works in combat. Ring changes made in combat apply after.

| Input | Action |
|---|---|
| Hold key, release on slice | Use |
| Release in the middle | Ring stays open |
| Click, or 1-9, 0 | Use |
| Right-click | Back |
| Esc | Close |
| Gamepad: stick, then release or A, L1, R1, L2, R2 | Use |
| Gamepad: B | Back or close |

| Command | Does |
|---|---|
| `/halo layout a` · `b` | Window layout |
| `/halo reset yes` | Delete all rings and options |
| `/halo status` · `debug` · `camstate` | Diagnostics |

## Data

`WTF\Account\<account>\SavedVariables\Halo.lua` (`HaloDB`).

## Tests

```
lua5.1 tests/Smoke.lua
```

## More

[docs/Details.md](docs/Details.md): styles, folders, automatic lists, how it works.
