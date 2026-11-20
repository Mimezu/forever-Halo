# Changelog

## 0.9.40 — 2026-11-20

- Fixed: a pad button held when a ring opened, then let go, raised an error ("Cannot call restricted closure from insecure code") instead of going back to the ring

## 0.9.39 — 2026-11-20

- Open Halo keycap shares the key tables with the ring keycaps
- Loot, mounts and zones no longer rebind ring keys or rebuild rings when nothing changed

## 0.9.38 — 2026-11-20

- Fixed: hold R2, press R3, let both go: the R2 ring stayed on screen but the R3 ring's slice was used. A ring opened on a layer (second button held first) now stays that ring until it closes

## 0.9.37 — 2026-11-20

- Fixed: hold R2, press R3, use a slice: Blizzard's bar stayed on its R2 page after R2 was let go. A pad button already held when a ring opens is no longer bound by the ring, so its release reaches the game. Once let go, the ring takes it back (at once out of combat, at the next ring input in combat), and a layer button let go returns to the opening ring

## 0.9.36 — 2026-11-20

- Fixed: Blizzard's R2 bar stopped switching. A gamepad chord's second button (R2, L1...) no longer runs through Halo's relay: holding it, then pressing the ring's button, is read from the pad itself at the press, so R2 and L1 stay the game's own. Keyboard chords keep the relay

## 0.9.35 — 2026-11-20

- **Fishing pole**, a new slice (**+** › Fishing pole): one press puts your best fishing pole from the bags in your hands, the next puts back the weapons you held (main hand and off hand). Several poles: the best you can use. No pole: a short note, nothing else happens
- The swap is shared with Gamepad Companion (Choose › Quick use › Fishing pole): one file, `MimezuFishing.lua`, ships in both addons and the newest copy loaded runs. Each addon remembers your weapons per character, so either works alone
- It works in combat too: the macro's conditions (`[equipped:Fishing Poles]`) pick the way at the press. Its pole and weapons are re-read when your bags or hands change, out of combat
