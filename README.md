# FycoPvP

A single PvP interface for WoW 3.3.5a (Wrath of the Lich King), built to replace a stack of
overlapping addons with one that shares a single event handler and a single timer.

Replaces: TidyPlates + PlateBuffs (nameplates and their auras), TellMeWhen (tracking),
LoseControl (CC on you), SoundAlerter (voice cues), and Cheese (proc overlays).

**Interface:** 30300 · **SavedVariables:** `FycoPvPDB` (account), `FycoPvPLog` and
`FycoPvPArchive` (per character)

---

## Contents

- [Install](#install)
- [First five minutes](#first-five-minutes)
- [The modules](#the-modules)
- [Command reference](#command-reference)
- [Options panels](#options-panels)
- [Moving things around](#moving-things-around)
- [Sounds and voice](#sounds-and-voice)
- [Battle logs and the improvement algorithm](#battle-logs-and-the-improvement-algorithm)
- [Bring your own AI](#bring-your-own-ai)
- [What it cannot do](#what-it-cannot-do)
- [Troubleshooting](#troubleshooting)

---

## Install

**[Download the latest release](https://github.com/Karimmm33/FycoPvP/releases/latest)**, extract it
into `Interface\AddOns\`, and restart the client. The zip already contains a correctly named
`FycoPvP` folder, so there is nothing to rename.

Disable the addons it replaces so they do not fight over the same screen space.

> **Do not use the green *Code → Download ZIP* button.** GitHub names that archive after the branch,
> so it extracts as `FycoPvP-main`, and WoW requires the folder name to match `FycoPvP.toc`. The
> addon will not appear in the AddOns list at all, and the bundled sounds and textures are looked up
> by absolute path, so they would not load either. Use the release zip, or `git clone` straight into
> your AddOns folder:
>
> ```
> git clone https://github.com/Karimmm33/FycoPvP.git
> ```

Built for **3.3.5a (Interface 30300)**. On any other client version WoW greys it out as out of date
— tick *Load out of date AddOns* on the character-selection AddOns screen.

Everything is on by default. Individual modules can be switched off in the options panel, or left
running at effectively no cost — most do nothing outside combat.

## First five minutes

```
/fyco                 open the options panel
/fyco lock            unlock every frame, drag them, run it again to lock
/fyco status          what is loaded and what is cached
/fyco help            the full command list, in game
```

Frame positions save themselves the moment you drop them.

---

## The modules

### Control — what is holding you
One large icon while you are crowd controlled: the spell, a cooldown swipe, a countdown, and a
border coloured by category (stun, fear, silence, root, and so on). Reads `UnitDebuff("player")`
directly, so the duration shown is the real one, not a guess from the combat log.

### Procs — your own windows
An icon row for the procs that change what you press: Nightfall, Backdraft, Molten Core,
Decimation, Eradication, Backlash. Each proc can also flash a coloured overlay at the screen edges,
in the style of Blizzard's spell activation art, and the overlay **pulses for as long as the proc is
live** rather than flashing once.

`/fyco procs` previews every overlay in turn. `/fyco stop` ends the preview.

### Casts — cast bars
Player, target and focus, each with icon, spell name, remaining time, and a colour that tells you
whether you can interrupt it:

| Colour | Meaning |
| --- | --- |
| Yellow | interruptible — kick it |
| Grey | not interruptible — do not waste the kick |
| Blue | your own cast |
| Light blue | your own channel (drains rather than fills) |

Blizzard's own cast bars are hidden by default. `/fyco blizz` puts them back (needs `/reload`).

### Auras — target and focus
Two rows answering two different questions:

- **Top row** — what *they* have up that changes what you should cast (defensives, immunities, and
  any CC they are sitting in)
- **Bottom row** — what *you* have on them, so you know when to refresh

**Show every debuff** (Options → FycoPvP → Debuffs, or `/fyco debuffs all`) turns the bottom row
into the whole picture instead: every debuff on the unit, not only yours. Yours stay **first, at
full size, with a solid coloured border**; everyone else's follow, smaller and dimmed. Their
defensives and any CC they are sitting in stay on the top row either way, so this never moves CC
somewhere you might break it by accident.

Yours are decided by *who cast it* — the API is asked — rather than by a table of spell IDs, so a
rank you have not trained yet can never quietly fall out of the row.

**Hover any icon for the real tooltip** — the spell, what it does, and the live remaining-time
line, exactly as Blizzard's own buff frames show it. The same applies to the Dispel buff bar. The
tooltip comes from the game rather than from the addon, so the text is never out of date. Icons
release the mouse while frames are unlocked, so hovering can't interfere with dragging.

### Alerts — stop casting now
The loud layer, in two parts. A big centred icon with a countdown when an enemy pops a defensive
worth reacting to (Spell Reflection, Ice Block, Divine Shield, Anti-Magic Shell…), highest priority
winning. And a fading banner when someone trinkets.

### Cooldowns — DR and enemy cooldowns
Two rows that follow your target and focus:

- **Diminishing returns** per category, per target: `100% → 50% → 25% → IMMUNE`, with the time
  until the category resets. This answers "how long until my fear is a full fear again".
- **Enemy cooldowns**, started when the ability is *seen used*, never inferred from the gap between
  uses. If an ability ever comes back sooner than the table expects, the tracker corrects itself
  downward and says so — `/fyco cds` prints what it has learned.

### Plates — nameplates
Rebuilt Blizzard plates rather than replacements: class colours, class icon, level, health value
and percentage, and your debuffs above the bar in a deterministic order.

Pets and NPCs are shrunk and faded so they cannot crowd out real players. Hiding allies uses the
`nameplateShowFriends` console variable, so those plates are never created at all.

Also shows the **inferred spec** under the bar, with healers marked in green — see *Spec* below.

**Show every debuff** (Options → FycoPvP → Debuffs, or `/fyco debuffs plates`) extends the aura row
from "your debuffs and their defensives" to every debuff on the unit. The order is their defensives,
then **your debuffs at full size**, then everyone else's — smaller and dimmed — and eight icons fit.

Be aware of what the timers can and cannot say here. On your own **target and focus** the game is
asked directly, so those countdowns are exact. On any *other* plate a debuff you did not cast is
known only from the combat log, which in 3.3.5a reports no duration at all — so it draws an icon
with **no number under it** rather than a guess. That is the main reason this is off by default.

`/fyco plates` lists the settings; `/fyco plates <setting> <number>` changes one.
`/fyco auras` explains why a particular plate is showing what it shows, and marks which debuffs
on your target are yours.

### Dispel — the target and focus buff bar
Does two separate jobs, deliberately kept apart:

**1. It shows every buff, on anyone.** Friendly, neutral or hostile, with icon,
cooldown sweep, timer and stack count. This is a full replacement for Blizzard's
target buff row — tick *Hide Blizzard's buff row* and use this instead. Debuffs
are left alone.

**2. It highlights what you could actually strip.** Those are drawn larger, pulse,
and are outlined in their dispel type's colour (Magic blue, Curse purple, Disease
brown, Poison green). Sorted so the highlighted one is always leftmost.

Highlighting needs **all three** to be true:

- the buff's dispel type is one you ticked (Magic, for a warlock)
- **the unit is hostile** — there is nothing to strip off a friend
- the watch list is empty, *or* the buff is on it

**The watch list is empty by default, which means every dispellable buff glows.**
You opt in to seeing *less*, not more. Load the built-in list of things that
actually matter — Fear Ward, Hand of Freedom, Power Word: Shield, Ice Barrier,
Earth Shield, Bloodlust and the rest — with `watch defaults`.

Being straight about the generic part: in 3.3.5a **only Magic can be removed
from an enemy**. Purge, Spellsteal, Dispel Magic and Devour Magic all take Magic
and nothing else, and Curse/Poison/Disease removal only works on friendly
targets. The other three boxes exist because the module is generic, not because
ticking Poison will find you something to dispel off a rogue.

One honest caveat on detection: `UnitBuff` often returns an empty dispel type for
a buff on a hostile unit even when it is plainly magic, while `isStealable` —
the flag Spellsteal uses — is set. So a buff counts as Magic if **either** says
so. That is a heuristic. `/fyco dispel debug` prints what the API actually
returned for your target and what this module decided, so if the core disagrees
you can see it rather than guess.

```
/fyco dispel                   current settings
/fyco dispel magic             toggle a type (magic/curse/poison/disease)
/fyco dispel showall           every buff, or only dispellable ones
/fyco dispel blizzard          hide Blizzard's own buff row
/fyco dispel target            toggle the target row
/fyco dispel focus             toggle the focus row
/fyco dispel watch             what is on the watch list
/fyco dispel watch Fear Ward   add or remove a buff
/fyco dispel watch defaults    load the built-in list
/fyco dispel watch clear       empty it, so everything dispellable glows
/fyco dispel debug             what the game says about your target's buffs
```

### Cooldown numbers — on everything
Countdown text on every cooldown in the game: action bars, items, bags, the pet
bar. This is what OmniCC does, built in, so OmniCC is no longer needed.

**It stands down automatically if OmniCC is enabled**, because two addons
drawing on one icon gives you two numbers. Disable OmniCC and `/reload` to use
this instead. FycoPvP's own icons opt out (`noCooldownCount`) since they draw
their own timers, and any other addon using that same flag is honoured too.

```
/fyco cdtext                  current settings
/fyco cdtext fontSize 20      any numeric setting
/fyco cdtext scaletext        toggle scaling text to icon size
/fyco cdtext hidemodel        toggle Blizzard's sweep animation
```

Settings: `minDuration` (3s — hides the global cooldown), `tenths` (show tenths
below 3s), `mmss` (M:SS format below N seconds, 0 = off), `fontSize`,
`minFontSize` (text below this hides rather than becoming an unreadable smear),
`scaleText`, `hideModel`. Colour shifts with urgency: white minutes, yellow
seconds, red under 5.5s.

Ported from **OmniCC 3.0.4 by Tuller**, used under the MIT licence; the
copyright notice is in the header of `Modules/CDText.lua`. Rather than copy the
file — which needs `Classy-1.0`, `LibStub` and OmniCC's own 514-line config
module — the timing logic was carried across: text updates are scheduled for
exactly when the displayed string would next change, rather than every frame.

### Bar — your own cooldown bar
A private action bar showing only the cooldowns you choose, anywhere you want. Handles three kinds
of entry, because they need three different APIs: normal spells (tracked by name, so they follow
you across ranks), **pet** spells such as Spell Lock, and items.

```
/fyco track Spell Lock      add something
/fyco track                 list what is tracked, numbered
/fyco untrack 3             remove one
```

### Buffs — what is missing
Watches a list of buffs and shows **only the ones that are missing**. When everything is up the
frame hides completely. Silent by design — it is a reminder, not an alert.

Defaults for Affliction: Fel Armor, Soul Link, Soulstone Resurrection, and a pet.

```
/fyco buff Fel Armor        add
/fyco buff                  list, numbered
/fyco unbuff 2              remove
```

### Spec — who is what, and who is the healer
Works out an enemy's spec from the spells they cast, and marks healers in green on the nameplate.

**This is inference, not fact.** 3.3.5a exposes no spec for anyone but you, and hostile inspection
is blocked. A priest who casts Penance is Discipline; a priest who has cast nothing is just a
priest, and nothing is claimed. The spec with the most sightings wins, so a Holy paladin who taps
Crusader Strike once is not relabelled Retribution.

Also calls out **drinking** enemies. Arena-only by default, because in a battleground somebody is
always drinking and the call becomes noise.

```
/fyco spec                  who we think is what, and how many sightings back it
/fyco drink                 dump enemy buffs, to correct drink detection
```

### Range — can I actually hit this
There is no distance API in 3.3.5a, so the check is anchored to a real spell you know. A readout
shows `IN RANGE` / `OUT OF RANGE`, and your target's name greys out on its nameplate when you are
too far away.

If the answer cannot be determined it says **unknown** rather than guessing — a grey readout you can
see beats a red one that lies.

```
/fyco range                 which spell is used, and the class default
/fyco range Shadow Bolt     use a different one
/fyco range default         back to the class default
```

### Lockout — interrupts, both directions
When *you* get kicked: a draining bar naming the locked school and the time left. When your *target*
gets kicked: a line telling you their healer cannot heal right now.

This is a different question from the enemy cooldowns above. That row says *when their Counterspell
is back*; this says *what can be cast right now*.

### Recap — what killed you
A rolling window of everything that happens to you, printed when you die: every hit with its
timestamp, your health at each step, the CC you were in, and a by-source breakdown.

```
/fyco recap                 replay your last death
/fyco recap now             show the current window without dying (good for testing)
```

### Stats — are you actually improving
Counts the things that decide games, across three scopes:

| Scope | Resets |
| --- | --- |
| **match** | every time you enter an arena or battleground |
| **session** | after 2 hours idle, or `/fyco stats reset` |
| **lifetime** | never on its own — `/fyco stats reset all` |

The session is saved per character and survives a `/reload`, because reloading is something you do
mid-evening and it should not cost you your numbers. It rolls over on its own once enough idle time
passes, which is what makes "tonight" and "last Tuesday" separate without you pressing anything.

Counted: interrupts landed and wasted, times you were kicked and for how long, CC landed, CC that
ended early, CC thrown into diminished categories, enemy trinkets seen, dispels both ways, deaths,
and killing blows.

```
/fyco stats                 the table, plus a short "reading it" assessment
/fyco stats help            what every row means
/fyco stats reset           end the session now
/fyco stats reset all       clear lifetime too
```

### Archive — every game, kept
See [Battle logs](#battle-logs-and-the-improvement-algorithm).

### Announce — telling your team
Optional party chat output for the CC you land (with its DR level), your interrupts, enemy
trinkets, drinking, and enemy defensives.

**Off by default**, and hard-capped at 5 messages per 15 seconds with a minimum 1.5s gap, no matter
what is enabled. Those limits are not configurable — an addon that floods a battleground gets its
owner muted rather than thanked. Defaults to `PARTY`, not `BATTLEGROUND`.

```
/fyco announce              current settings
/fyco announce on           enable
/fyco announce party|bg|raid|say
/fyco announce cc           toggle one category
```

### Logger — measuring the truth
The combat log reports spell IDs but never durations or cooldowns, so the tables shipped here start
as assumptions. The logger times each aura from applied to removed, and each repeat cast of a
tracked cooldown, then reports where reality disagrees.

It also flags **ID mismatches** — auras whose name matches something tracked but whose ID is not in
the table. This is how Spell Reflection got fixed: warriors cast `23920`, but the buff that lands is
`59725` or `36096`, so the alert never fired.

```
/fyco log                   what has been measured, and what disagrees
```

---

## Command reference

Every command is `/fyco <something>`. `/fycopvp` also works.

| Command | What it does |
| --- | --- |
| `/fyco` | open the options panel |
| `/fyco help` | list commands in game |
| `/fyco status` | modules loaded, units and auras cached |
| `/fyco lock` | unlock/lock every frame for dragging |
| `/fyco perrow <1-20>` | icons per row before a bar wraps (default 7) |
| `/fyco debug` | toggle debug output |
| **Display** | |
| `/fyco plates` | list nameplate settings |
| `/fyco plates <setting> <number>` | change one (e.g. `petScale 0.7`) |
| `/fyco plates petauras` | toggle auras on pet plates |
| `/fyco debuffs` | show the debuff tracker's settings |
| `/fyco debuffs all` | bar: every debuff, or only your own |
| `/fyco debuffs plates` | nameplates: every debuff, or only your own |
| `/fyco debuffs mine <10-48>` | size of your own debuff icons on the bar |
| `/fyco debuffs other <10-48>` | size of everyone else's on the bar |
| `/fyco auras` | why the target's plate shows what it shows |
| `/fyco dispel [type\|target\|focus\|untracked]` | which enemy buff types to track |
| `/fyco dispel debug` | what the game says about your target's buffs |
| `/fyco cdtext [setting] [n]` | cooldown numbers on your action bars |
| `/fyco pos <player\|target\|focus> <x> <y>` | place a cast bar by MoveAnything coordinates |
| `/fyco scale <player\|target\|focus> <n>` | resize a cast bar |
| `/fyco blizz` | toggle Blizzard's cast bars (needs `/reload`) |
| **Tracking** | |
| `/fyco track [spell]` | list or add to your cooldown bar |
| `/fyco untrack <n>` | remove one by number |
| `/fyco buff [name]` | list or add to the missing-buff watch |
| `/fyco unbuff <n>` | remove one by number |
| `/fyco range [spell\|default]` | which spell the range check uses |
| `/fyco cds` | enemy cooldowns, corrected against the table |
| **Intel** | |
| `/fyco spec` | inferred specs and how sure we are |
| `/fyco drink` | dump enemy buffs, to fix drink detection |
| `/fyco announce [...]` | party announce settings |
| **History** | |
| `/fyco recap [now]` | replay your last death, or show the live window |
| `/fyco stats [reset\|reset all\|help]` | match / session / lifetime counters |
| `/fyco games [clear]` | every recorded game, newest last |
| `/fyco game <n>` | the full report for one game |
| `/fyco log` | measured durations vs the shipped tables |
| **Sound** | |
| `/fyco sound` | toggle all sound |
| `/fyco sounds` | play every fallback cue |
| `/fyco voices` | audition the whole voice pack |
| `/fyco voice` | list voice lines flagged as wrong-language |
| `/fyco voice <spellID> <file>` | point a spell at a different recording |
| `/fyco procs` | preview each proc overlay |
| `/fyco stop` | stop any preview |

---

## Options panels

Under **Interface → AddOns**:

- **FycoPvP** — every module on/off, sound, frame unlock, test buttons
- **FycoPvP → Nameplates** — visibility, content, colours, pet and NPC sizing
- **FycoPvP → Debuffs** — show every debuff or only your own, on the target/focus bar and on
  nameplates, plus the two icon sizes
- **FycoPvP → Combat** — healer announce, drinking, interrupt sound, death recap window, session
  length, party announce
- **FycoPvP → Dispel** — which enemy buff types to track, where to show them, icon sizes

Everything here matches a `/fyco` command, so the two stay in step whichever you use. Changes apply
immediately — **Plates is the one exception** and needs a `/reload`, because it rewrites Blizzard's
plate regions and undoing that cleanly at runtime is not worth the complexity.

Every panel scrolls, so a panel with more settings than fits simply scrolls rather than spilling
its widgets over the game world — which is what used to happen.

## Moving things around

`/fyco lock` unlocks every frame and fills it with placeholder content so you can see what you are
dragging. Run it again to lock. Positions save on drop.

**Every bar wraps after 7 icons** and continues on a second row — target and focus buffs, their
defensives, your DoTs, the DR row, enemy cooldowns, procs, missing buffs and your cooldown bar all
share one setting, so they stay consistent with each other:

```
/fyco perrow 5        or the Icons per row slider on the main panel
```

A bar set to grow downward wraps into a second *column* instead, which is the same rule seen
sideways. Nameplate auras are the deliberate exception — they sit above a moving nameplate, where a
second row would collide with the plate above, so they stay on one line.

Cast bars can also be placed by coordinates, using the same anchor and numbers MoveAnything shows,
so values copy straight across:

```
/fyco pos target 758.3 263.3
/fyco scale target 1.1
```

## Sounds and voice

Spoken cues fire for trinkets, fears, saps, reflects and more. `/fyco voices` plays the whole pack
so you can hear what is there; `/fyco voice <spellID> <file>` repoints any spell at a different
recording. Files live in `FycoPvP\Voice\`.

Ten lines are synthetic (Windows speech synthesis) because the original pack had no English
recording for them — `/fyco voice` lists which. Swap any of them for your own `.mp3`.

---

## Battle logs and the improvement algorithm

**Every arena and battleground is recorded as its own row.** Not a running total — a separate record
per game, so any single game can be read back on its own.

Each record holds: the date, zone and duration, the result, your spec, the full roster with class and
inferred spec per player, your counters for that match, every death with what killed you and the
damage that did it, and a capped timeline of CC, interrupts, trinkets and defensives.

In game:

```
/fyco games          every game, numbered, newest last
/fyco game 7         one game in full
/fyco games clear    wipe the archive
```

### Cost

This is the part built most carefully, because it runs while you play. It registers **no timer**,
adds **no combat-log handler of its own**, and does nothing whatsoever outside an arena or
battleground. Every fact it stores already passes through the addon's shared event bus for another
module, so the parsing cost was already paid — it only keeps a copy. The record is built in memory
and written once, when the match ends.

The archive keeps the **last 60 games** as a ring buffer so the saved-variables file cannot grow
without bound, and lives in its own SavedVariable (`FycoPvPArchive`) — if it ever bloats, deleting
that one file costs you no settings.

### Seeing the algorithm's results without any AI

Two places, neither of which needs a model:

**1. In game.** `/fyco stats` prints the match / session / lifetime table *and* a short
**"reading it"** section — up to three prompts generated from your own numbers, ranked by how much
they matter. Each has a minimum sample size and stays silent until there is enough data, so it will
not lecture you about two wasted kicks out of three. For example:

```
reading it (this session)
  - kicked 13 times for 74 seconds total, about 5.7s each. That is the
    window they kill you in - fake-cast before the real one.
```

**2. Out of game.** A companion tool reads the archive and computes the deeper statistics:
time-to-death per enemy class, which class actually kills you and how much of the damage was theirs,
how often you died with **no defensive used in the 10 seconds before**, DR discipline, interrupt
accuracy, and a recent-versus-previous trend. Plain arithmetic, no model involved:

```
python -m wowcoach import      read new games out of the saved variables
python -m wowcoach overall     the rollup
python -m wowcoach killers     what kills you
python -m wowcoach matchups    winrate and survival by enemy class
python -m wowcoach trend       recent games against the ones before
python -m wowcoach games       list them
python -m wowcoach game 12     one in full
```

Games only reach disk when you **`/reload` or log out** — WoW holds saved variables in memory until
then. That is the one thing to remember.

---

## Bring your own AI

The archive is a plain Lua table in a saved-variables file, so anything that can read a file can read
your games. Nothing is encrypted, obfuscated, or sent anywhere.

```
WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\FycoPvP.lua
```

```lua
FycoPvPArchive = {
  ["v"] = 1,
  ["matches"] = {
    {
      ["id"] = "20260922-230411",      -- sortable, unique per match
      ["t"] = 1758578651,              -- epoch seconds, start
      ["ended"] = 1758579011,
      ["dur"] = 360,
      ["kind"] = "arena",              -- or "pvp" for a battleground
      ["zone"] = "Nagrand Arena",
      ["result"] = "loss",
      ["resultSrc"] = "inferred",      -- "api" | "inferred" | "unknown"
      ["me"] = { ["class"] = "WARLOCK", ["spec"] = "Affliction", ["level"] = 80 },
      ["roster"] = { { ["name"]=…, ["class"]=…, ["spec"]=…, ["role"]=…, ["side"]=… } },
      ["stats"]  = { ["kicksLanded"] = 4, … },
      ["deaths"] = { { ["at"]=84.2, ["killer"]=…, ["killerClass"]=…,
                       ["top"] = { { ["src"]=…, ["spell"]=…, ["amount"]=… } } } },
      ["events"] = { { ["t"]=12.4, ["e"]="cc", ["by"]="me", ["on"]=…, ["lvl"]=1 } },
    },
  },
}
```

The most reliable way to parse it is to **execute it in a Lua interpreter** and read the globals —
it is Lua, so Lua is the only parser guaranteed to agree with the client about quoting, escapes and
number formats. Strip `io` and `os` from that state first, out of habit.

**If you feed this to a model, carry the uncertainty through.** `resultSrc` says whether the result
was reported or deduced. Specs are inferred from observed casts. "CC that ended early" cannot
separate a damage break from a dispel from a trinket. A model handed these numbers without those
caveats will produce confident nonsense.

`SCHEMA` in `Modules/Archive.lua` is bumped whenever the record shape changes, so check `v`.

---

## What it cannot do

Honest limits, most of them imposed by the 3.3.5a client:

- **No addon can cast, target, or swap focus for you.** Those are protected and need a hardware
  event. Nothing here automates play, and nothing could.
- **No network access.** WoW addons cannot make HTTP requests. Anything outside the game reads the
  saved-variables file after the fact.
- **Enemy spec is inference**, always. There is no API, and hostile inspection is blocked.
- **Match results may be deduced.** `GetBattlefieldWinner()` is not verified on every private core,
  so a result may come from working out who was left standing. The record says which.
- **The combat log has no raid flags** in 3.3.5a (those arrived in 4.0), and gives spell IDs but
  never durations, so some values are measured rather than read. That is what the Logger is for.
  This is also why a nameplate showing *every* debuff draws other people's without a countdown:
  away from your own target and focus there is no duration to show, and inventing one would be
  worse than showing none.
- **Nameplates have no unit tokens** in this version. They are matched to units by name, which is why
  two mobs sharing a name can confuse the aura display.

## Troubleshooting

**Auras stopped showing on a nameplate.** `/fyco auras` with that unit targeted explains what the
plate resolved to and why.

**An alert never fires for a spell you keep seeing.** The cast ID and the buff ID differ for some
spells. `/fyco log` lists auras whose name matches something tracked but whose ID is not in the
table — paste it and the table can be corrected.

**A cooldown looks wrong.** `/fyco cds` shows where observed reality disagrees with the shipped
value. The tracker only ever corrects downward, because a reuse earlier than predicted is hard
evidence while a long gap proves nothing.

**Nameplate changes did nothing.** Plates is the one module that needs `/reload`.

**A voice line is in the wrong language.** `/fyco voice` lists the suspect ones;
`/fyco voice <spellID> <file>` repoints them.

**Nothing in `/fyco games`.** Games are written when a match *ends*. If one is missing you may have
left before it finished, or not reloaded since.

---

## Credits and licence

The addon's own code is MIT licensed — see [LICENSE](LICENSE). The media bundled with it is not
mine, and is included on these terms:

- **`Voice/`** — 58 spoken cues from the freely redistributable Russian SoundAlerter voice pack by
  **Andrewqtx**. Not all lines match every spell perfectly; `/fyco voice` lists the suspect ones and
  `/fyco voice <spellID> <file>` repoints them.
- **`Textures/`** — Blizzard's own spell-activation overlay art (`Nightfall`, `Molten_Core`,
  `Sudden_Doom`, `Backlash`, `Imp_Empowerment`, `GenericArc_*`), as used by the default UI. World of
  Warcraft and its assets are trademarks of Blizzard Entertainment. This project is unaffiliated
  with and unendorsed by Blizzard.

If you own any of the above and would rather it were not distributed here, open an issue and it will
be removed.
