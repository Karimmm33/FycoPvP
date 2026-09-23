--[[ FycoPvP - Data.lua
     Spell tables. Everything is keyed by spell ID, never by localised name:
     a wrong name string fails silently, a wrong ID fails loudly at load.
     Values marked VERIFY are retail 3.3.5a assumptions that the Logger module
     is meant to confirm or correct against Frostmourne.                      ]]

local ADDON, ns = ...

-- Crowd control that lands on YOU. cat = what it does, dr = DR bucket.
-- Ranks are listed individually; there is no name-based fallback by design.
ns.CC = {}

local function add(cat, dr, ...)
	for i = 1, select("#", ...) do
		ns.CC[select(i, ...)] = { cat = cat, dr = dr }
	end
end

--        cat        dr           spell IDs (all ranks)
add("stun",      "stun",      5211, 6798, 8983)                    -- Bash
add("stun",      "stun",      22570, 49802)                        -- Maim
add("stun",      "stun",      9005, 9823, 9827, 27006, 49803)      -- Pounce
add("stun",      "stun",      853, 5588, 5589, 10308)              -- Hammer of Justice
add("stun",      "stun",      408, 8643)                           -- Kidney Shot
add("stun",      "stun",      1833)                                -- Cheap Shot
add("stun",      "stun",      30283, 30413, 30414, 47846, 47847)   -- Shadowfury
add("stun",      "stun",      20253, 20614, 20615, 25273, 25274)   -- Intercept
add("stun",      "stun",      7922)                                -- Charge Stun
add("stun",      "stun",      12809)                               -- Concussion Blow
add("stun",      "stun",      20549)                               -- War Stomp
add("stun",      "stun",      46968)                               -- Shockwave
add("stun",      "stun",      44572)                               -- Deep Freeze
add("stun",      "stun",      47481)                               -- Gnaw (ghoul)
add("stun",      "stun",      19577)                               -- Intimidation
add("stun",      "stun",      12355)                               -- Impact

add("fear",      "fear",      5782, 6213, 6215)                    -- Fear
add("fear",      "fear",      5484, 17928)                         -- Howl of Terror
add("fear",      "fear",      6789, 17925, 17926, 27223, 47859, 47860) -- Death Coil
add("fear",      "fear",      8122, 8124, 10888, 10890)            -- Psychic Scream
add("fear",      "fear",      5246)                                -- Intimidating Shout
add("fear",      "fear",      1513)                                -- Scare Beast

add("horror",    "horror",    64044)                               -- Psychic Horror
add("horror",    "horror",    6358)                                -- Seduction

add("incap",     "incap",     118, 12824, 12825, 12826)            -- Polymorph
add("incap",     "incap",     51514)                               -- Hex
add("incap",     "incap",     6770, 2070, 11297)                   -- Sap
add("incap",     "incap",     1776, 1777, 8629, 11285, 11286, 38764) -- Gouge
add("incap",     "incap",     20066)                               -- Repentance
add("incap",     "incap",     3355, 14308, 14309)                  -- Freezing Trap Effect
add("incap",     "incap",     2637, 18657, 18658)                  -- Hibernate
add("incap",     "incap",     19503)                               -- Scatter Shot
add("incap",     "incap",     51209)                               -- Hungering Cold

add("silence",   "silence",   15487)                               -- Silence
add("silence",   "silence",   18469)                               -- Counterspell - Silenced
add("silence",   "silence",   34490)                               -- Silencing Shot
add("silence",   "silence",   1330)                                -- Garrote - Silence
add("silence",   "silence",   47476)                               -- Strangulate
add("silence",   "silence",   24259)                               -- Spell Lock
add("silence",   "silence",   25046, 28730, 50613)                 -- Arcane Torrent
add("silence",   "silence",   55021)                               -- Improved Counterspell

add("disorient", "disorient", 2094)                                -- Blind
add("disorient", "disorient", 31661)                               -- Dragons Breath

add("root",      "root",      339, 1062, 5195, 5196, 9852, 9853, 26989, 53308) -- Entangling Roots
add("root",      "root",      122, 865, 6131, 10230, 27088, 42917) -- Frost Nova
add("root",      "root",      19306)                               -- Counterattack
add("root",      "root",      19185, 19387, 19388)                 -- Entrapment
add("root",      "root",      23694)                               -- Improved Hamstring
add("root",      "root",      33395)                               -- Freeze (water elemental)

add("disarm",    "disarm",    676)                                 -- Disarm
add("disarm",    "disarm",    51722)                               -- Dismantle
add("disarm",    "disarm",    64058)                               -- Psychic Horror (disarm)

add("cyclone",   "cyclone",   33786)                               -- Cyclone
add("charm",     "charm",     605)                                 -- Mind Control
add("sleep",     "incap",     700)                                 -- Sleep

-- Display priority when several are on you at once. Higher wins.
ns.CCPriority = {
	cyclone = 100, charm = 95, fear = 90, horror = 88, stun = 85,
	incap = 80, sleep = 78, silence = 70, disorient = 65,
	root = 40, disarm = 35,
}

-- Colour per category, used by Control and later by Plates.
ns.CCColor = {
	stun      = { 0.85, 0.20, 0.20 },
	fear      = { 0.65, 0.25, 0.85 },
	horror    = { 0.50, 0.15, 0.70 },
	incap     = { 0.95, 0.75, 0.20 },
	sleep     = { 0.95, 0.75, 0.20 },
	silence   = { 0.25, 0.55, 0.95 },
	disorient = { 0.95, 0.55, 0.20 },
	root      = { 0.30, 0.75, 0.55 },
	disarm    = { 0.60, 0.60, 0.60 },
	cyclone   = { 0.90, 0.90, 0.95 },
	charm     = { 0.80, 0.30, 0.60 },
}

-- Sound cues. Keys are referenced by name so modules never hardcode a path.
-- Verify every one actually plays with: /fyco sounds
ns.Sounds = {
	trinket   = "Sound\\Interface\\RaidWarning.wav",
	reflect   = "Sound\\Interface\\RaidWarning.wav",
	immune    = "Sound\\Doodad\\BellTollNightElf.wav",
	fear      = "Sound\\Interface\\AuctionWindowOpen.wav",
	sap       = "Sound\\Interface\\AuctionWindowClose.wav",
	defensive = "Sound\\Doodad\\G_Chimes01.wav",
	interrupt = "Sound\\Interface\\MapPing.wav",
	ccbreak   = "Sound\\Interface\\AuctionWindowClose.wav",
}

-- Enemy spells that deserve a sound and an alert. VERIFY durations on Frostmourne.
-- sound = key into ns.Sounds, prio = alert weight, dur = seconds (0 = read from API).
ns.Defensives = {
	[23920] = { name = "Spell Reflection",     sound = "reflect",   prio = 100, dur = 5 },
	-- The warrior CASTS 23920, but the buff that lands is one of these. Both
	-- were observed on Frostmourne by the logger; keying only on the cast ID is
	-- why the alert never fired.
	[59725] = { name = "Spell Reflection",     sound = "reflect",   prio = 100, dur = 5 },
	[36096] = { name = "Spell Reflection",     sound = "reflect",   prio = 100, dur = 5 },
	[42292] = { name = "PvP Trinket",          sound = "trinket",   prio = 100, dur = 0 },
	[48707] = { name = "Anti-Magic Shell",     sound = "immune",    prio = 95,  dur = 5 },
	[642]   = { name = "Divine Shield",        sound = "immune",    prio = 95,  dur = 12 },
	[45438] = { name = "Ice Block",            sound = "immune",    prio = 95,  dur = 10 },
	[59752] = { name = "Every Man for Himself", sound = "trinket",  prio = 92,  dur = 0 },
	[19263] = { name = "Deterrence",           sound = "immune",    prio = 90,  dur = 5 },
	[31224] = { name = "Cloak of Shadows",     sound = "immune",    prio = 90,  dur = 5 },
	[10278] = { name = "Hand of Protection",   sound = "immune",    prio = 90,  dur = 10 },
	[18499] = { name = "Berserker Rage",       sound = "fear",      prio = 88,  dur = 10 },
	[7744]  = { name = "Will of the Forsaken", sound = "fear",      prio = 88,  dur = 5 },
	[46924] = { name = "Bladestorm",           sound = "fear",      prio = 85,  dur = 6 },
	[34471] = { name = "The Beast Within",     sound = "fear",      prio = 85,  dur = 10 },
	[47585] = { name = "Dispersion",           sound = "defensive", prio = 85,  dur = 6 },
	[498]   = { name = "Divine Protection",    sound = "defensive", prio = 80,  dur = 12 },
	[33206] = { name = "Pain Suppression",     sound = "defensive", prio = 80,  dur = 8 },
	[6346]  = { name = "Fear Ward",            sound = "fear",      prio = 80,  dur = 180 },
	[49039] = { name = "Lichborne",            sound = "fear",      prio = 80,  dur = 10 },
	[48792] = { name = "Icebound Fortitude",   sound = "defensive", prio = 75,  dur = 12 },
	[871]   = { name = "Shield Wall",          sound = "defensive", prio = 75,  dur = 12 },
	[22812] = { name = "Barkskin",             sound = "defensive", prio = 70,  dur = 12 },
	[6940]  = { name = "Hand of Sacrifice",    sound = "defensive", prio = 70,  dur = 12 },
	[30823] = { name = "Shamanistic Rage",     sound = "defensive", prio = 65,  dur = 15 },
	[61336] = { name = "Survival Instincts",   sound = "defensive", prio = 65,  dur = 20 },
	[51052] = { name = "Anti-Magic Zone",      sound = "defensive", prio = 65,  dur = 10 },
	[50461] = { name = "Anti-Magic Zone",      sound = "defensive", prio = 65,  dur = 10 },  -- observed aura id
	[1044]  = { name = "Hand of Freedom",      sound = "defensive", prio = 60,  dur = 10 },
}

-- Voice cues, one per spell ID, played in preference to the category cue above.
-- Files live in FycoPvP\Voice\ (copied in, so nothing depends on SoundAlerter
-- remaining installed). Extension is added by Core; do not include it here.
ns.VoiceDir = "Interface\\AddOns\\FycoPvP\\Voice\\"
ns.Voice = {
	-- enemy defensives and immunities
	[23920] = "SpellReflection",   [42292] = "Trinket",
	[59725] = "SpellReflection",   [36096] = "SpellReflection",
	[50461] = "antiMagicZone",
	[48707] = "AntiMagicShell",    [642]   = "DivineShield",
	[45438] = "IceBlock",          [59752] = "Trinket",
	[19263] = "Deterrence",        [31224] = "CloakofShadows",
	[10278] = "HandofProtection",  [1044]  = "HandofFreedom",
	[6940]  = "handofsacrifice",   [47585] = "Dispersion",
	[498]   = "DivineProtection",  [33206] = "PainSuppression",
	[48792] = "IceboundFortitude", [871]   = "ShieldWall",
	[22812] = "Barkskin",          [30823] = "ShamanisticRage",
	[61336] = "SurvivalInstincts", [51052] = "antiMagicZone",
	-- fear immunity: your Fear is about to be wasted
	[18499] = "BerserkerRage",     [7744]  = "WillOfTheForsaken",
	[6346]  = "FearWard",          [49039] = "Lichborne",
	[46924] = "Bladestorm",        [34471] = "TheBeastWithin",
	-- crowd control landing on you
	[5782]  = "Fear",   [6213]  = "Fear",   [6215]  = "Fear",
	[8122]  = "Fear",   [8124]  = "Fear",   [10888] = "Fear",  [10890] = "Fear",
	[5246]  = "Fear",
	[5484]  = "Fear",        [17928] = "Fear",
	[6789]  = "DeathCoil",   [17925] = "DeathCoil", [17926] = "DeathCoil",
	[27223] = "DeathCoil",   [47859] = "DeathCoil", [47860] = "DeathCoil",
	[6358]  = "seduction",
	[6770]  = "sap",    [2070]  = "sap",    [11297] = "sap",
	[1776]  = "gouge",  [1777]  = "gouge",  [8629]  = "gouge",
	[11285] = "gouge",  [11286] = "gouge",  [38764] = "gouge",
	[118]   = "Polymorph", [12824] = "Polymorph", [12825] = "Polymorph",
	[12826] = "Polymorph",
	[51514] = "Hex",       [20066] = "Repentance", [2094]  = "Blind",
	[33786] = "Cyclone",   [51209] = "Hungeringcold", [19503] = "scatterShot",
	[15487] = "silence",   [47476] = "Strangulate",
	[18469] = "Counterspell", [55021] = "Counterspell", [24259] = "SpellLock",
	[408]   = "kidney",    [8643]  = "kidney",     [1833]  = "cheapShot",
	[853]   = "hammerofjustice", [5588] = "hammerofjustice",
	[5589]  = "hammerofjustice", [10308] = "hammerofjustice",
	[12809] = "concussionBlow",  [46968] = "shockwave",
	[20253] = "intercept", [20614] = "intercept", [20615] = "intercept",
	[25273] = "intercept", [25274] = "intercept",
	[7922]  = "charge",
	[676]   = "disarm",    [51722] = "dismantle",
}

-- Enemy CC worth a sound when it lands on a teammate or on you.
ns.CCSound = {
	fear = "fear", horror = "fear", incap = "sap",
	stun = "ccbreak", silence = "interrupt", cyclone = "immune",
}

-- Your own procs. Read straight off UNIT_AURA on the player, so no duration needed.
-- CONFIRMED on Frostmourne 2026-09-21 from the logger: 17941, 34936, 54277, 64371.
-- The logger had me wrong on two of these: Backdraft is 54277 (I had 47283) and
-- Backlash is 34936 (I had 54277, i.e. Backdraft's ID on the wrong spell).
ns.Procs = {
	[17941] = "Shadow Trance",   -- Nightfall       CONFIRMED
	[54277] = "Backdraft",       --                 CONFIRMED
	[34936] = "Backlash",        --                 CONFIRMED
	[64371] = "Eradication",     --                 CONFIRMED
	[71165] = "Molten Core",     -- VERIFY: not seen in the sample
	[63167] = "Decimation",      -- VERIFY: not seen in the sample
	[63165] = "Decimation",      -- VERIFY: alternate ID, harmless if wrong
}

-- Screen-edge art per proc, Blizzard's spell-activation style. Files copied from
-- the Cheese addon into FycoPvP\Textures\, so nothing depends on Cheese staying
-- installed. Anything not listed falls back to ns.ProcOverlayDefault.
-- Each proc gets its own art, colour and screen position, so the three cues
-- together are recognisable at a glance without reading the icon.
--   art   = file in FycoPvP\Textures\ (shape)
--   color = vertex tint {r,g,b}
--   pos   = "SIDES" (mirrored left+right) or "TOP" (single band)
ns.TextureDir = "Interface\\AddOns\\FycoPvP\\Textures\\"
ns.ProcOverlayDefault = { art = "GenericArc_01", color = { 1.00, 0.85, 0.20 }, pos = "SIDES" }
ns.ProcOverlay = {
	-- Shadow Trance: purple, the classic Nightfall look
	[17941] = { art = "Nightfall",     color = { 0.65, 0.25, 1.00 }, pos = "SIDES" },
	-- Backlash: hot red, sides
	[34936] = { art = "Backlash",      color = { 1.00, 0.25, 0.15 }, pos = "SIDES" },
	-- Molten Core: orange, sides
	[71165] = { art = "Molten_Core",   color = { 1.00, 0.55, 0.05 }, pos = "SIDES" },
	-- Eradication: cyan, and along the TOP so it cannot be confused with the rest
	[64371] = { art = "Sudden_Doom",   color = { 0.20, 0.95, 0.95 }, pos = "TOP"   },
	-- Backdraft: gold, sides
	[54277] = { art = "GenericArc_05", color = { 1.00, 0.80, 0.15 }, pos = "SIDES" },
	-- Decimation: green, TOP
	[63167] = { art = "GenericTop_01", color = { 0.35, 1.00, 0.35 }, pos = "TOP"   },
	[63165] = { art = "GenericTop_01", color = { 0.35, 1.00, 0.35 }, pos = "TOP"   },
}

-- Overlay timings in seconds: ramp in, hold, fade out. Used for the one-shot
-- preview, and as the fade-out timing when a proc ends.
ns.FlashIn, ns.FlashHold, ns.FlashOut = 0.12, 0.70, 0.70

-- While a proc is still active the overlay breathes between these two alphas
-- rather than sitting at a flat brightness -- it stays readable for a ten
-- second Eradication without turning into wallpaper.
ns.FlashPulseMin, ns.FlashPulseMax, ns.FlashPulsePeriod = 0.22, 0.55, 1.3

-- Your DoTs, for the Auras module at step 4. All CONFIRMED from the same log.
ns.MyDots = {
	[30405] = "Unstable Affliction",
	[59161] = "Haunt",
	[27216] = "Corruption",
	[47812] = "Corruption",
	[27218] = "Curse of Agony",
	[27215] = "Immolate",
	[17962] = "Conflagrate",
	[32391] = "Shadow Embrace",
	[30909] = "Curse of Weakness",
	[27217] = "Drain Soul",
}

-- Interrupts: cooldown and the lockout they apply. VERIFY on Frostmourne.
ns.Interrupts = {
	[1766]  = { name = "Kick",         cd = 10, lock = 5 },
	[6552]  = { name = "Pummel",       cd = 10, lock = 4 },
	[2139]  = { name = "Counterspell", cd = 24, lock = 8 },
	[47528] = { name = "Mind Freeze",  cd = 10, lock = 4 },
	[19647] = { name = "Spell Lock",   cd = 24, lock = 6 },
	[57994] = { name = "Wind Shear",   cd = 6,  lock = 2 },
	[72]    = { name = "Shield Bash",  cd = 12, lock = 6 },
}

ns.DR_RESET = 18 -- seconds after the aura fades. VERIFY: private cores vary.

-- A representative spell per DR category, used only for its icon texture.
ns.DRIcon = {
	stun      = 408,    -- Kidney Shot
	fear      = 5782,   -- Fear
	horror    = 6358,   -- Seduction
	incap     = 118,    -- Polymorph
	sleep     = 700,
	silence   = 15487,  -- Silence
	disorient = 2094,   -- Blind
	root      = 122,    -- Frost Nova
	disarm    = 676,    -- Disarm
	cyclone   = 33786,
	charm     = 605,
}

ns.DRLabel = { [1] = "100%", [2] = "50%", [3] = "25%", [4] = "IMMUNE" }
ns.DRLevelColor = {
	[1] = { 0.30, 0.85, 0.35 },
	[2] = { 0.95, 0.85, 0.20 },
	[3] = { 0.95, 0.50, 0.15 },
	[4] = { 0.90, 0.15, 0.15 },
}

-- Enemy cooldowns worth tracking per player. Started when we SEE the ability
-- used, never inferred from the gap between uses -- the logger showed gaps are
-- only an upper bound (Ice Block came back at 265s against a 300s cooldown
-- because Cold Snap reset it). If we ever see a reuse earlier than the value
-- here, the tracker corrects this number downward at runtime and says so.
-- always = show the slot even before it has been used (you know they have it).
ns.EnemyCD = {
	[42292] = { name = "PvP Trinket",      cd = 120, always = true,  prio = 100 },
	[59752] = { name = "Every Man",        cd = 120, always = false, prio = 100 },
	[7744]  = { name = "WotF",             cd = 120, always = false, prio = 95  },
	[23920] = { name = "Spell Reflection", cd = 10,  always = false, prio = 90  },
	[642]   = { name = "Divine Shield",    cd = 300, always = false, prio = 88  },
	[45438] = { name = "Ice Block",        cd = 300, always = false, prio = 88  },
	[19263] = { name = "Deterrence",       cd = 90,  always = false, prio = 85  },
	[31224] = { name = "Cloak of Shadows", cd = 90,  always = false, prio = 85  },
	[48707] = { name = "Anti-Magic Shell", cd = 45,  always = false, prio = 85  },
	[10278] = { name = "Hand of Protection", cd = 300, always = false, prio = 84 },
	[47585] = { name = "Dispersion",       cd = 120, always = false, prio = 80  },
	[18499] = { name = "Berserker Rage",   cd = 30,  always = false, prio = 75  },
	-- interrupts: knowing theirs is down is a free cast window
	[1766]  = { name = "Kick",             cd = 10,  always = false, prio = 70  },
	[6552]  = { name = "Pummel",           cd = 10,  always = false, prio = 70  },
	[2139]  = { name = "Counterspell",     cd = 24,  always = false, prio = 70  },
	[47528] = { name = "Mind Freeze",      cd = 10,  always = false, prio = 70  },
	[19647] = { name = "Spell Lock",       cd = 24,  always = false, prio = 70  },
	[57994] = { name = "Wind Shear",       cd = 6,   always = false, prio = 70  },
}

-- These ten lines had no English recording in the SoundAlerter pack -- the
-- files shipped there came from the Russian fork. They were regenerated with
-- Windows speech synthesis (Microsoft David), compressed and loudness-matched
-- to the rest of the pack. They are synthetic, so they do not sound quite like
-- the human recordings; swap any of them with:
--   /fyco voice <spellID> <filename>
ns.VoiceSynthetic = {
	kidney = true, cheapShot = true, charge = true, intercept = true,
	gouge = true, shockwave = true, concussionBlow = true, dismantle = true,
	windShear = true, antiMagicZone = true,
}
ns.VoiceSuspect = ns.VoiceSynthetic  -- kept: /fyco voice still lists these

-- Dispel-type colours for debuff borders. Same palette PlateBuffs used, so the
-- two read consistently if both are ever running.
ns.DebuffColor = {
	Magic   = { 0.20, 0.60, 1.00 },
	Curse   = { 0.60, 0.00, 1.00 },
	Disease = { 0.60, 0.40, 0.00 },
	Poison  = { 0.00, 0.60, 0.00 },
	none    = { 0.80, 0.25, 0.20 },
}

----------------------------------------------------------------------
-- spec inference
----------------------------------------------------------------------

-- DELIBERATE EXCEPTION to the "IDs, never names" rule at the top of this file.
-- Every rank of a spell has its own ID, so keying Mortal Strike by ID means
-- listing six of them and still missing the seventh. Spec inference is also
-- the one feature here that degrades gracefully: a name we fail to match just
-- leaves the spec unknown, it does not break a timer or a bar. So this table
-- is keyed by the ENGLISH spell name, resolved from the combat log's spell ID
-- through GetSpellInfo. On a non-English client it silently finds nothing.
--
-- role drives the display colour and the healer mark:
--   healer  bright green    caster  light blue
--   melee   orange          tank    grey
ns.SpecSpells = {}

local function spec(class, label, role, ...)
	for i = 1, select("#", ...) do
		ns.SpecSpells[select(i, ...)] = { class = class, spec = label, role = role }
	end
end

spec("DRUID",   "Resto",   "healer", "Swiftmend", "Wild Growth", "Nourish",
                                     "Tree of Life", "Living Seed", "Revitalize")
spec("DRUID",   "Boomkin", "caster", "Starfall", "Moonkin Form", "Typhoon",
                                     "Insect Swarm", "Force of Nature", "Eclipse")
spec("DRUID",   "Feral",   "melee",  "Mangle", "Savage Roar", "Berserk",
                                     "Survival Instincts", "Tiger's Fury")
spec("DRUID",   "Bear",    "tank",   "Lacerate", "Swipe (Bear)", "Maul")

spec("PALADIN", "Holy",    "healer", "Holy Shock", "Beacon of Light",
                                     "Divine Favor", "Divine Illumination", "Sacred Shield")
spec("PALADIN", "Ret",     "melee",  "Crusader Strike", "Divine Storm",
                                     "Repentance", "The Art of War")
spec("PALADIN", "Prot",    "tank",   "Avenger's Shield", "Hammer of the Righteous",
                                     "Holy Shield", "Shield of Righteousness")

spec("PRIEST",  "Disc",    "healer", "Penance", "Power Infusion", "Pain Suppression",
                                     "Divine Aegis", "Rapture", "Inner Focus")
spec("PRIEST",  "Holy",    "healer", "Circle of Healing", "Guardian Spirit",
                                     "Prayer of Mending", "Lightwell", "Desperate Prayer")
spec("PRIEST",  "Shadow",  "caster", "Mind Flay", "Vampiric Touch", "Dispersion",
                                     "Shadowform", "Devouring Plague", "Vampiric Embrace",
                                     "Mind Sear", "Psychic Horror", "Silence")

spec("SHAMAN",  "Resto",   "healer", "Riptide", "Earth Shield", "Mana Tide Totem",
                                     "Earthliving Weapon", "Tidal Force", "Chain Heal")
spec("SHAMAN",  "Ele",     "caster", "Lava Burst", "Thunderstorm", "Elemental Mastery",
                                     "Totem of Wrath")
spec("SHAMAN",  "Enh",     "melee",  "Stormstrike", "Lava Lash", "Feral Spirit",
                                     "Shamanistic Rage", "Maelstrom Weapon", "Windfury Weapon")

spec("MAGE",    "Frost",   "caster", "Ice Barrier", "Icy Veins", "Summon Water Elemental",
                                     "Cold Snap", "Deep Freeze", "Frostbite")
spec("MAGE",    "Fire",    "caster", "Combustion", "Living Bomb", "Dragon's Breath",
                                     "Blast Wave", "Hot Streak", "Pyroblast")
spec("MAGE",    "Arcane",  "caster", "Arcane Power", "Presence of Mind",
                                     "Arcane Barrage", "Slow", "Missile Barrage")

spec("WARLOCK", "Affli",   "caster", "Unstable Affliction", "Haunt", "Siphon Life",
                                     "Shadow Embrace", "Everlasting Affliction")
spec("WARLOCK", "Demo",    "caster", "Metamorphosis", "Demonic Empowerment",
                                     "Soul Link", "Immolation Aura", "Molten Core")
spec("WARLOCK", "Destro",  "caster", "Chaos Bolt", "Conflagrate", "Shadowfury",
                                     "Backdraft", "Shadowburn")

spec("WARRIOR", "Arms",    "melee",  "Mortal Strike", "Bladestorm", "Sweeping Strikes",
                                     "Taste for Blood", "Overpower")
spec("WARRIOR", "Fury",    "melee",  "Bloodthirst", "Death Wish", "Rampage", "Heroic Fury")
spec("WARRIOR", "Prot",    "tank",   "Shield Slam", "Devastate", "Shockwave",
                                     "Last Stand", "Vigilance", "Concussion Blow")

spec("ROGUE",   "Assa",    "melee",  "Mutilate", "Cold Blood", "Hunger for Blood")
spec("ROGUE",   "Combat",  "melee",  "Blade Flurry", "Adrenaline Rush", "Killing Spree")
spec("ROGUE",   "Sub",     "melee",  "Shadowstep", "Premeditation", "Shadow Dance",
                                     "Preparation", "Hemorrhage")

spec("HUNTER",  "BM",      "caster", "Bestial Wrath", "Intimidation", "The Beast Within")
spec("HUNTER",  "MM",      "caster", "Chimera Shot", "Silencing Shot", "Readiness",
                                     "Trueshot Aura", "Aimed Shot")
spec("HUNTER",  "Surv",    "caster", "Explosive Shot", "Black Arrow", "Wyvern Sting",
                                     "Lock and Load")

spec("DEATHKNIGHT", "Blood",  "tank",  "Heart Strike", "Vampiric Blood", "Mark of Blood",
                                       "Dancing Rune Weapon", "Rune Tap")
spec("DEATHKNIGHT", "Frost",  "melee", "Howling Blast", "Frost Strike", "Hungering Cold",
                                       "Unbreakable Armor", "Killing Machine")
spec("DEATHKNIGHT", "Unholy", "melee", "Scourge Strike", "Summon Gargoyle", "Bone Shield",
                                       "Unholy Blight", "Ghoul Frenzy", "Anti-Magic Zone")

ns.RoleColor = {
	healer = { 0.20, 1.00, 0.35 },
	caster = { 0.45, 0.75, 1.00 },
	melee  = { 1.00, 0.60, 0.20 },
	tank   = { 0.70, 0.70, 0.70 },
}

-- Drinking. Also name-matched: the aura ID differs per drink item, and on a
-- private core it may differ again. If none of these ever fire, /fyco drink
-- prints what the enemy actually has so the list can be corrected.
ns.DrinkAuras = {
	["Drink"]        = true,
	["Food"]         = true,
	["Food & Drink"] = true,
	["Refreshment"]  = true,
}

----------------------------------------------------------------------
-- range check
----------------------------------------------------------------------

-- IsSpellInRange needs a spell you actually know, so this is a per-class
-- default rather than a fixed distance. Override with /fyco range <spell>.
-- Melee classes get their melee opener, which is the range that matters.
ns.RangeSpell = {
	WARLOCK     = "Corruption",        -- 30y, the affliction opener
	MAGE        = "Frostbolt",         -- 30y
	PRIEST      = "Shadow Word: Pain", -- 30y
	DRUID       = "Moonfire",          -- 30y
	SHAMAN      = "Lightning Bolt",    -- 30y
	PALADIN     = "Exorcism",          -- 30y
	HUNTER      = "Serpent Sting",     -- 35y
	DEATHKNIGHT = "Icy Touch",         -- 30y
	WARRIOR     = "Rend",              -- melee
	ROGUE       = "Sinister Strike",   -- melee
}

----------------------------------------------------------------------
-- spell schools, for the interrupt lockout display
----------------------------------------------------------------------

-- Combat log school is a bitmask; an interrupt locks the whole school it hit.
ns.School = {
	[1]  = { "Physical", 1.00, 1.00, 0.60 },
	[2]  = { "Holy",     1.00, 0.90, 0.50 },
	[4]  = { "Fire",     1.00, 0.35, 0.15 },
	[8]  = { "Nature",   0.35, 0.90, 0.35 },
	[16] = { "Frost",    0.45, 0.80, 1.00 },
	[32] = { "Shadow",   0.65, 0.35, 0.95 },
	[64] = { "Arcane",   0.85, 0.50, 1.00 },
}

----------------------------------------------------------------------
-- enemy buffs worth removing
----------------------------------------------------------------------

-- The four dispel types the UI lets you tick. Colours come from
-- ns.DebuffColor, which already carries them.
ns.DispelTypes = { "Magic", "Curse", "Poison", "Disease" }

-- Which types a class can strip off an ENEMY. This only picks sensible
-- defaults for the tick boxes; every type stays tickable regardless.
--
-- Worth being straight about: in 3.3.5a, offensive dispelling is a Magic-only
-- affair. Purge, Spellsteal, Dispel Magic and the Felhunter's Devour Magic all
-- take Magic and nothing else, and Curse/Poison/Disease removal only ever
-- works on friendly targets. The other three are offered because the module is
-- generic and a server change may use them -- not because ticking Poison will
-- find you something to dispel off a rogue today.
ns.ClassOffensiveDispel = {
	WARLOCK = { Magic = true },   -- Felhunter: Devour Magic
	MAGE    = { Magic = true },   -- Spellsteal
	SHAMAN  = { Magic = true },   -- Purge
	PRIEST  = { Magic = true },   -- Dispel Magic, offensively
}

-- Enemy buffs that change what you should do about them, by NAME.
--
-- Name-keyed for the reason given in CLAUDE.md: Power Word: Shield has a dozen
-- ranks and a dozen IDs, and missing one here costs a highlight, not a timer.
-- prio 3 = drop everything and dispel it, 2 = worth a global, 1 = nice to have.
ns.DispelPriority = {
	-- stops your crowd control outright
	["Fear Ward"]              = 3,
	["Hand of Freedom"]        = 3,
	["Blessing of Freedom"]    = 3,
	-- absorbs, which also soak the damage that would break your own CC
	["Power Word: Shield"]     = 3,
	["Ice Barrier"]            = 3,
	["Sacred Shield"]          = 2,
	["Divine Aegis"]           = 2,
	-- immunities and damage reduction
	["Hand of Protection"]     = 3,
	["Blessing of Protection"] = 3,
	["Hand of Sacrifice"]      = 2,
	["Pain Suppression"]       = 2,
	-- healing over time: dispelling these is most of a healer's throughput
	["Renew"]                  = 2,
	["Rejuvenation"]           = 2,
	["Regrowth"]               = 2,
	["Lifebloom"]              = 2,
	["Wild Growth"]            = 2,
	["Riptide"]                = 2,
	["Earth Shield"]           = 3,
	["Prayer of Mending"]      = 2,
	-- throughput and burst cooldowns
	["Bloodlust"]              = 3,
	["Heroism"]                = 3,
	["Power Infusion"]         = 2,
	["Innervate"]              = 2,
	["Divine Favor"]           = 2,
	["Arcane Power"]           = 2,
	["Icy Veins"]              = 2,
	["Combustion"]             = 2,
	["Water Shield"]           = 1,
	["Lightning Shield"]       = 1,
	["Inner Focus"]            = 1,
	["Fel Armor"]              = 1,
	["Mana Shield"]            = 1,
}
