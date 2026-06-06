# Moonlander keymap recommendations (Emacs + xmonad)

**Status:** Recommendation / not yet flashed
**Last updated:** 2026-06-05
**Hardware:** ZSA Moonlander Mark I (USB 3297:1972), configured via Oryx/keymapp
**See also:** `caps-ctrl.md` (Framework internal keyboard saga), `scripts/setup-moonlander.sh` (udev rules)

The stack has three specific demands: Emacs (dense `C-` and `M-` chords),
xmonad with **mod = Ctrl+Alt** (`myModMask = controlMask .|. mod1Mask`), and
the us/ru toggle via `grp:shifts_toggle`.

---

## Core idea: modifiers on thumbs, layers instead of reaching

### Base layer (QWERTY — keep it, the RU xkb layer depends on positions)

```
┌─────┬───┬───┬───┬───┬───┬───┐   ┌───┬───┬───┬───┬───┬───┬─────┐
│  =  │ 1 │ 2 │ 3 │ 4 │ 5 │Esc│   │ ⇧⇧│ 6 │ 7 │ 8 │ 9 │ 0 │  -  │
├─────┼───┼───┼───┼───┼───┼───┤   ├───┼───┼───┼───┼───┼───┼─────┤
│ Tab │ Q │ W │ E │ R │ T │Hyp│   │Meh│ Y │ U │ I │ O │ P │  \  │
├─────┼───┼───┼───┼───┼───┼───┘   └───┼───┼───┼───┼───┼───┼─────┤
│⎋/Ctl│ A │ S │ D │ F │ G │           │ H │ J │ K │ L │ ; │'/Ctl│
├─────┼───┼───┼───┼───┼───┤           ├───┼───┼───┼───┼───┼─────┤
│ Sft │ Z │ X │ C │ V │ B │           │ N │ M │ , │ . │ / │ Sft │
└─┬───┼───┼───┼───┼───┼───┘           └───┼───┼───┼───┼───┼───┬─┘
  │ ` │Cmp│ ← │ → │L2 │                   │L2 │ ↓ │ ↑ │ [ │ ] │
  └───┴───┴───┴───┴───┘                   └───┴───┴───┴───┴───┘
       ┌─────┬─────┬─────┐           ┌─────┬─────┬─────┐
       │Space│ Ctrl│ XMod│           │ XMod│ Meta│Enter│
       │ /L1 │     │(red)│           │(red)│     │ /L1 │
       └─────┴─────┴─────┘           └─────┴─────┴─────┘

```

### The decisions that matter

1. **`XMod` = the big red thumb keys = `LCtrl+LAlt` held together**
   (in Oryx: add both modifiers to one key). Every single xmonad bind —
   `M-Space`, `M-o`, `M-S-j`, `C-M-q` — becomes one thumb + one finger.
   The single biggest win for this config.

2. **Ctrl on the left thumb, Meta (Alt) on the right thumb** — kills Emacs
   pinky. `C-x C-s`, `M-x`, `C-M-f` all become thumb-rolls. Keep them as
   plain holds (not mod-taps) — dedicated thumb modifiers never misfire.

3. **`Esc/Ctrl` dual-function on the Caps position** — exactly the KMonad
   `(tap-hold-next-release 200 esc lctl)` alias, but in firmware. Mirror it
   with **`'/Ctrl` on the right pinky** so right-hand chords (`C-p`, `C-n`
   in rofi) don't need crossing over.

4. **`⇧⇧` (top right) = macro: `LShift+RShift`** — fires `grp:shifts_toggle`
   for RU in one keypress. Worth testing; if xkb doesn't register the
   simultaneous press from one event, switch xkb to `grp:caps_toggle` or
   `grp:win_space_toggle` and map a dedicated key instead.

5. **Space and Enter as layer-taps** (`tap: Space / hold: L1`) — this is
   what thumb clusters are for.

### Layer 1 — Nav + Num (held via Space/Enter)

- `H J K L` → `← ↓ ↑ →` — works *everywhere*, not just Emacs
- Right-hand numpad block on `M,./JKL/UIO` (or digits on the top row)
- `B`/`N` → PgUp/PgDn, `Y`/`O` → Home/End
- Optionally Ctrl pre-applied on a pair of keys for cheap word-motion
  (`C-←`/`C-→`)

### Layer 2 — Symbols + media

- `()[]{}<>` under the strong fingers of both home rows — for
  Haskell/Elisp this matters more than anything
- Brightness/volume/media on the left block (xmonad already handles the
  `XF86` keys)
- A `RESET`/bootloader key so flashing never needs the paperclip

---

## Firmware settings (Oryx → advanced)

- **Tapping term ~200 ms** (matches the KMonad value already in use)
- **Permissive hold: ON** for the `Esc/Ctrl` keys — commits to hold when
  another key goes down+up inside the window, i.e. the same semantics as
  KMonad's `tap-hold-next-release`. Without it, fast `C-s` taps will
  produce `Esc s`.
- **Skip home-row mods** for now: with this much Emacs chording they
  misfire constantly while typing; thumb mods + the two pinky Ctrls cover
  everything with zero false positives.

---

## Integration notes

- Once the layout settles, **export the source from Oryx** ("Download
  source") and commit it to the repo — e.g. `~/.config/xmonad/moonlander/`.
  It can be built with ZSA's QMK fork later without Oryx if combos/custom
  code beyond Oryx are ever needed.
- The `setxkbmap` line in `xmonad.hs` applies `ctrl:nocaps` globally —
  fine, composes with this layout (the Moonlander never sends Caps anyway);
  the *internal* Framework keyboard keeps its current behavior, unchanged.
