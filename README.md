# Halo

Small radial menus for Forever: potions, food, mounts, pets, emotes, markers and
small utility spells. A light take on OPie, drawn with Forever's own gamepad flyout art.
Works with keyboard, mouse and gamepad, in combat, with the interface hidden, and in
Frame Gambit's Cinematic Mode.

Type `/halo` to open the window.

## Using a ring

**Keyboard and mouse**
- Hold the ring's key. The ring opens at the mouse cursor (or a fixed position you choose, see Options).
- Point at a slice and let go of the key: it is used.
- Let go in the middle and the ring stays open. Then click a slice, or press its number (1–9, 0).
- Click the middle, press Esc or the ring key again to close. Another ring's key opens that ring.
  Right-click goes back from a nested ring, or closes.

**Gamepad**
- Hold the ring's button. In the gamepad interface the ring opens at its gamepad position
  (right side by default; Options → Gamepad → Ring position → Place).
- Tilt the right stick toward a slice and let go of the button: it is used.
- Or let go first, then tilt and press confirm: A, L1, R1, L2 or R2 (except a button your ring's key
  uses). Cancel (PAD2) goes back or closes.
- **Tap mode** (Options → Gamepad → Ring button: Tap): tap the button to open the ring (it stays
  open when you let go), point, tap again to use the slice. A tap with the stick centred closes.
  Another ring's button opens that ring instead.
- **Stick released** (Options → Gamepad), what letting go of the stick does:
  - **Keep**: the slice you pointed at stays selected; use it with the ring button or a confirm button.
  - **Use**: point at a slice and let go of the stick, and it is used, like Blizzard's own radial
    menus. To close without using anything, press the ring's button again (Tap) or B before
    letting go. To change your mind, move
    around the edge rather than through the middle.
  Keep and Use work in combat too.
- The stick you point with does nothing else while a ring is open (Options → Gamepad): the camera
  stays still with the right stick (you can still walk), walking stops with the left stick. This
  works in combat too. After a ring closes, the stick comes back once it is centred. "Block both
  sticks" takes both. The "How to use" box in Options shows only what applies to your settings.
- Combinations such as R1 + D-pad down: click **Macro** in the ring editor and put the macro on that
  slot of Blizzard's gamepad bars. Each button alone keeps its normal action. A ring opened by its
  macro works like tap mode.

A ring with nothing to show (for example no potions in your bags) says so and does not open.

## Styles

Five styles, all drawn with art that ships with Forever. Compare them on the **Styles** tab
(click a preview to replay its opening), pick a default there, or give a ring its own style
with the **Style** button in the ring editor.

- **A Flyout** — Forever's gamepad flyout: dark disc, round slots, cursor arrow. Blooms open.
- **B Action bar** — vanilla action buttons floating in a circle, all fading in together;
  hotkey numbers top-right like the real bars.
- **C Minimap** — minimap tracking buttons around a dark minimap disc, quest-arrow pointer;
  sweeps open like a compass.
- **D Runes** — the keystone rune circle, slowly turning, with a breathing glow, affix
  rings and a glowing hover. No pointer.
- **E Parchment** — a round parchment with gilded portrait rings and a dark pointer; unfolds.

## Window layouts

The footer's **Layout A | B** switch (or `/halo layout a` / `/halo layout b`) picks how the window
is drawn. Both have the same settings; A is the classic window and the default.

- **B, Rings**: a header line with the ring's icon, name, **Only this character** and a **...** menu
  (Duplicate, Make macro, Delete ring with a confirmation step); keys and style on one line; a
  bigger ring; beside it an inspector for the selected slice (or how to fill the ring when none is
  selected) and a **This ring** card (Hide what you can't use, Show tooltips, Spacing). The ring
  list hides its scroll bar while everything fits and marks the selected ring with a gold bar.
- **B, Options**: one label column and one control column; choices and steppers sit in one plate;
  rows that depend on another (Show slice numbers, the fixed position) show only while they apply;
  explanations are in the rows' tooltips.

## Making rings

- **New ring**, then give it a **Key** and/or a **Gamepad** button. Click the button, then press
  the key. Backspace clears it. The note under the keys says what that key did before.
- **Macro** makes a macro that opens the ring (for gamepad bar combinations).
- Drag spells, items, mounts, toys, battle pets, macros or equipment sets onto the **+** in the
  middle of the ring. Dropping onto a slice replaces it.
- Click **+** for emotes, target markers, other rings (nested), custom macros, and automatic lists.
- Drag a slice to move it around the ring (let go outside the ring to cancel). Click a slice to select it (Earlier/Later, Remove). Right-click a slice removes it.
- **Hide what you can't use now** leaves out unlearned spells and items not in your bags.
- **Only this character** keeps a ring (and its keys) to the current character.
- **Folders**: the list has a folder for this character, one for rings everyone uses, and one for
  each of your other characters (closed until you open them). A ring from another character is
  shown dimmed and locked; **Copy to this character** makes your own copy (it keeps its key and
  gamepad button unless something here already uses them, and nested rings that character alone
  could see are left out). **Copy for everyone** makes a shared copy. **Duplicate** copies your
  own ring into the same folder.

Automatic lists fill themselves outside combat: Potions (healthstones first), Elixirs and flasks, Food and drink,
Bandages, Scrolls, Favourite mounts (usable here; all mounts if you have no favourites),
Favourite pets.

Starter rings (no keys): Supplies, Travel, Emotes.

## How it works

- `Secure.lua` — one hidden SecureActionButton (`HaloButton`) receives every ring key via
  override bindings (`CLICK HaloButton:r<id>`). A SecureHandler wrap does everything that must
  work in combat in the restricted environment: open, find the pointed slice
  (`GetGamePadState` stick first, then `GetMousePosition`), set the slice's attributes and let the
  click perform it. While open, the button covers the screen to catch clicks (keyboard and mouse
  only), and temporary bindings add Esc, number keys, the gamepad confirm and cancel buttons,
  and the stick's directions (Keep the selection).
- Ring contents are compiled into the secure environment **outside combat only**. In combat the
  last build stays; changes apply when combat ends.
- Spells are cast by name, so they always use the highest rank you know.
- `Ring.lua` draws the ring and mirrors the same pointing rule, so the highlighted slice is the
  one that will be used. It has no parent (works with Alt-Z) and registers with Frame Gambit as a
  `quick_actions` scene provider.
- Camera: Forever refuses the camera-speed settings below 0.5, and an addon's own stick frame takes
  both sticks. So Halo borrows Blizzard's stick listener (the one its start-menu radial uses): a
  function in the slot of the stick you point with holds that stick (camera or walking) and lets the other through. Out of
  combat the listener is switched on when a ring opens and off when it closes. In combat that switch
  is blocked, so Halo switches it on (hidden) as the fight starts and shows or hides it per ring.
- Stick released (Keep / Use): the stick's four directions are real keys when the game's
  `GamePadStickAxisButtons` setting is on (Halo turns it on for these modes and puts it back
  after). While a ring is open they are bound to Halo, so the secure code sees each direction
  pressed and let go. A release with the stick back near the middle means it was let go (the game
  sometimes sends only one of the two releases of a diagonal, so Halo does not wait for both), and
  that key release is real input: the button can cast or use an item then, in combat too.
- Blizzard's own radials (class and pet flyouts such as the paladin auras, the start menu) close on
  any gamepad button press, and the stick's direction keys count. So while one is open (out of
  combat) Halo switches `GamePadStickAxisButtons` off and back on when it closes. In combat that is
  not attempted, so those radials do not work in combat.

No OPie code or art is used (OPie is all rights reserved); only the interaction ideas.

## Tests

From the addon folder: `lua5.1 tests/Smoke.lua`

The smoke test loads every file against a mocked client, runs the real secure snippets in an
emulated restricted environment and checks: starter rings, auto lists, key bindings, hold and
release, sticky mode, nested rings and back, switching between rings, number keys, gamepad stick
pick and confirm, tap mode, sticky selection, the camera hold in and out of combat, combat
deferral, empty rings, secure and visual pointing agreement for 1–12 slices, every style, and that
the window builds.

## Debug

`/halo debug` turns a log on (kept across /reload, saved to `HaloDB.debugLog` on /reload).
`/halo status` lists rings, slices and keys; `/halo camstate` shows who holds the camera stick.
