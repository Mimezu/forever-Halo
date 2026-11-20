# Changelog

## 0.9.35 — 2026-11-20

- **Fishing pole**, a new slice (**+** › Fishing pole): one press puts your best fishing pole from the bags in your hands, the next puts back the weapons you held (main hand and off hand). Several poles: the best you can use. No pole: a short note, nothing else happens
- The swap is shared with Gamepad Companion (Choose › Quick use › Fishing pole): one file, `MimezuFishing.lua`, ships in both addons and the newest copy loaded runs. Each addon remembers your weapons per character, so either works alone
- It works in combat too: the macro's conditions (`[equipped:Fishing Poles]`) pick the way at the press. Its pole and weapons are re-read when your bags or hands change, out of combat
