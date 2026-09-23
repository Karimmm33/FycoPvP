# FycoPvP — rules for working in this addon

WoW 3.3.5a (Interface 30300). Read this before changing anything here.

---

## HARD RULE 1 — never hand-place an options widget

**The Interface Options content area is roughly 500 x 500 pixels and does not
clip its children.** Widgets placed past the bottom are not cut off — they
render *outside the frame*, floating over the game world. That has now happened
twice, both times because Y offsets were computed by hand and a column grew past
the panel.

So:

- **Never write a literal Y offset for a widget.** Not once. Use the layout
  cursor in `Modules/Options.lua` (`Column:Check`, `:Slider`, `:Title`,
  `:Note`, `:Button`, `:Swatch`). Each advances the cursor by its own real
  height, so a column cannot silently overrun.
- **Every options panel must be a scroll frame.** `MakePanel()` builds one.
  Content longer than the view then scrolls instead of escaping.
- **After building a panel, call `Finish()`** so the scroll child is sized to
  the deepest column. Forget it and scrolling silently does nothing.
- **Two columns maximum**, at `COL1 = 8` and `COL2 = 250`, each 230 wide.
  A third column runs off the right edge — that was the first occurrence.
- Widget heights the cursor assumes: check 24, title 34, button 28, swatch 28,
  slider 48 (its min/max labels hang *below* it), note = measured with
  `GetStringHeight()` after the width is set.

If a panel is getting crowded, add a sub-panel. Do not shrink the gaps.

## HARD RULE 2 — write Lua with the Write/Edit tools

Bash heredocs and `python -c` in this environment silently eat backslashes.
`"Fonts\\FRIZQT__.TTF"` arrives as `"Fonts\FRIZQT__.TTF"`, an invalid Lua
escape, and the addon then refuses to load with no clue why. This has bitten
three times.

Author `.lua` content with Write/Edit. If a scripted patch is genuinely needed,
write the script to a file and run *that* — never `python - <<EOF`.

## HARD RULE 3 — compile-check before saying it is done

Every `.lua` file must parse, contain no non-ASCII characters (the 3.3.5a client
renders them as mojibake), and have no invalid escapes. Check all of them, not
only the ones you touched, then tell Karim to `/reload`.

## HARD RULE 4 — a Cooldown frame needs its template

`CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")`. Always. A bare
Cooldown frame is not initialised, and `SetCooldown` on one throws.

This is nastier than it sounds, because the error fires mid-update before
anything is shown, so the feature simply never appears — no error, no clue.
`Modules/Dispel.lua` shipped without it and its entire row was invisible while
its own debug command worked perfectly.

`Core.lua`'s ticker now runs inside a pcall and prints the error, so the next
one announces itself instead of hiding. That is not permission to be careless:
the pcall retires the offending module's updates until a `/reload`.

## HARD RULE 5 — the archive shape is a public interface

`FycoPvPArchive` (written by `Modules/Archive.lua`) is read by an external
analysis tool kept outside this repo. A renamed or dropped field errors nowhere — it just
becomes a silently empty column downstream. If the record shape changes, bump
`SCHEMA` in `Archive.lua` and update the consumer.

---

## Architecture

`Core.lua` owns everything shared, and modules must use it rather than
duplicating it:

- **one** event dispatcher — `ns:On(event, fn)`
- **one** 10 Hz ticker — `ns:OnTick(fn)`. Do not create your own `OnUpdate`
  unless the thing genuinely needs per-frame smoothness (only `Casts.lua` does).
- **one** combat log handler, publishing to a message bus —
  `ns:Subscribe(msg, fn)` / `ns:Fire(msg, ...)`. Adding a second
  `COMBAT_LOG_EVENT_UNFILTERED` handler is almost always wrong; subscribe to the
  bus instead. `Recap.lua` is the one exception, and its first line is a GUID
  comparison that rejects everything not aimed at the player.
- unit registry `ns.units[guid]`, aura cache `ns.auras[guid]`
- `ns:Enabled("modulename")` — checked every frame, so toggling a module takes
  effect immediately instead of needing a reload.

Modules register with `ns:Module("name")` and expose `OnLoad`. Add the file to
`FycoPvP.toc` and to the defaults table in `Core.lua`.

## 3.3.5a facts that keep mattering

- No `C_Timer`, no `CombatLogGetCurrentEventInfo`, no `NAME_PLATE_UNIT_ADDED`,
  no nameplate unit tokens.
- The combat log has **no raid flags** — those arrived in 4.0.
- It gives spell IDs but **never durations**; anything time-based is either
  measured (see `Logger.lua`) or hardcoded and marked VERIFY.
- **A cast ID is not always the buff ID.** Warriors cast Spell Reflection
  `23920` but the aura that lands is `59725` or `36096`. `/fyco log` reports
  these mismatches.
- `UnitClass()` returns a real class for NPCs and pets, not just players.
- **Never call `SetScale()` on a nameplate.** The engine writes its screen
  position every frame in unscaled coordinates, so a scaled plate lands at
  position/scale and drifts with the camera. Resize the health bar instead.
- Nameplate colours are set in C, so `hooksecurefunc` on `SetStatusBarColor`
  never fires. Recover the engine's colour by comparing against the last colour
  *we* wrote.
- `pairs()` order is unspecified for sparse integer keys like spell IDs, and
  rehashes on insert. Anything with a display limit must sort first.
- `UnitBuff` returns `name, rank, icon, count, dispelType, duration, expires,
  caster, isStealable, shouldConsolidate, spellId`. For buffs on an enemy,
  `dispelType` is often nil and `isStealable` is the more reliable "this is a
  magic buff you can remove" signal.

## Keying tables: IDs, except where ranks make it impossible

`Data.lua` is keyed by spell ID, because a wrong name fails silently while a
wrong ID fails loudly. A few tables deliberately break that rule and say so in a
comment: `ns.SpecSpells`, the interrupt lockout lookup, and `ns.DispelPriority`.
Mortal Strike has six ranks and six IDs, and a miss there degrades to "unknown",
not to a broken timer. Follow that precedent only when both halves hold.

## Honesty in the UI

Several features are inference, and the interface must never present them as
fact:

- enemy spec is deduced from observed casts — nothing is shown for an enemy who
  has cast nothing
- match results may be deduced from who was left standing; the record carries
  `resultSrc`
- "CC ended early" cannot separate a break from a dispel from a trinket
- range returns "unknown" when it cannot be determined, never "out of range"

When adding a feature that guesses, label the guess.

## Before telling Karim it is done

1. Every `.lua` parses, ASCII-only, no bad escapes.
2. New commands are in `Core.lua`'s slash handler *and* its `help` output.
3. New modules are in `FycoPvP.toc`, the `Core.lua` defaults table, and the
   options module list.
4. `README.md` covers any new feature and command.
