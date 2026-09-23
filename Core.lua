--[[ FycoPvP - Core.lua
     Shared plumbing every module reads. Four jobs:
       1. one event dispatcher and one throttled ticker for the whole addon
       2. unit registry   : GUID -> name, class, type (player / pet / npc)
       3. aura cache      : GUID -> active auras, from UnitAura where a token
                            exists, from the combat log everywhere else
       4. sound engine    : named cues with per-cue throttling
     3.3.5a notes: no C_Timer, no CombatLogGetCurrentEventInfo, and the combat
     log has NO raid-flag arguments (those arrived in 4.0).                    ]]

local ADDON, ns = ...

ns.units  = {}   -- [guid] = { name, class, utype, seen }
ns.auras  = {}   -- [guid] = { [spellID] = { expires, duration, stacks, mine, harmful } }
ns.player = nil  -- player GUID, set at PLAYER_LOGIN

local band       = bit.band
local GetTime    = GetTime
local UnitGUID   = UnitGUID
local UnitExists = UnitExists
local UnitBuff   = UnitBuff
local UnitDebuff = UnitDebuff
local tinsert    = table.insert

-- combat log object flags (3.3.5a)
local TYPE_PLAYER   = 0x00000400
local TYPE_PET      = 0x00001000
local TYPE_GUARDIAN = 0x00002000
-- reaction bits. The only cheap way to tell an enemy from an ally in a
-- battleground, where there are no unit tokens for either.
local REACT_HOSTILE  = 0x00000040
local REACT_NEUTRAL  = 0x00000020
local REACT_FRIENDLY = 0x00000010

----------------------------------------------------------------------
-- event dispatch
----------------------------------------------------------------------

local frame    = CreateFrame("Frame", ADDON .. "Core", UIParent)
local handlers = {}

--- Register fn to run on event. Several modules may take the same event.
function ns:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		frame:RegisterEvent(event)
	end
	tinsert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		list[i](event, ...)
	end
end)

----------------------------------------------------------------------
-- one ticker, 10 Hz, shared
----------------------------------------------------------------------

local tickers, dead, acc = {}, {}, 0
local current

function ns:OnTick(fn)
	tinsert(tickers, fn)
end

--- Run every ticker. Split out so the whole pass fits inside ONE pcall rather
--- than needing one per module -- ten protected calls a second, not a hundred.
local function RunTickers(now)
	for i = 1, #tickers do
		if not dead[i] then
			current = i
			tickers[i](now)
		end
	end
end

frame:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.1 then return end
	acc = 0

	local ok, err = pcall(RunTickers, GetTime())
	if not ok then
		-- Until this pcall existed, one module's bug took every other module's
		-- updates down with it, in complete silence: the error only surfaced
		-- if script errors happened to be switched on. That is how a missing
		-- CooldownFrameTemplate in Dispel made an entire row simply never
		-- appear. Retire the offender, say so out loud, let the rest run.
		dead[current or 0] = true
		ns:Print("|cffff4040a module errored and its updates were stopped:|r")
		ns:Print("  " .. tostring(err))
		ns:Print("|cff808080Everything else keeps running. "
		      .. "|cffffff00/reload|r to try it again.|r")
	end
end)

----------------------------------------------------------------------
-- output
----------------------------------------------------------------------

function ns:Print(...)
	local msg = ""
	for i = 1, select("#", ...) do
		msg = msg .. tostring(select(i, ...)) .. " "
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff8080ff" .. ADDON .. "|r " .. msg)
end

function ns:Debug(...)
	if FycoPvPDB and FycoPvPDB.debug then self:Print("|cff808080dbg|r", ...) end
end

----------------------------------------------------------------------
-- sound
----------------------------------------------------------------------

local lastPlayed = {}

--- Throttled playback. `id` is whatever we throttle on: a cue key or a spell ID.
local function play(id, path, throttle)
	if not (FycoPvPDB and FycoPvPDB.sounds) or not path then return end
	local now = GetTime()
	if lastPlayed[id] and (now - lastPlayed[id]) < (throttle or 1.5) then return end
	lastPlayed[id] = now
	PlaySoundFile(path)
	return true
end

--- Play a named cue from ns.Sounds. Throttled per key so a burst of combat
--- log events cannot machine-gun the same file.
function ns:Sound(key, throttle)
	local path = ns.Sounds[key]
	if not path then
		self:Debug("no sound for key", key)
		return
	end
	return play(key, path, throttle)
end

--- Preferred entry point: play this spell's own voice line if we have one,
--- otherwise fall back to the generic category cue. Throttles on the spell ID,
--- so two different spells never suppress each other.
function ns:SpellSound(spellID, fallbackKey, throttle)
	local override = spellID and FycoPvPDB.voiceOverride and FycoPvPDB.voiceOverride[spellID]
	local voice = override or (spellID and ns.Voice[spellID])
	if voice then
		return play(spellID, ns.VoiceDir .. voice .. ".mp3", throttle)
	end
	return self:Sound(fallbackKey, throttle)
end

----------------------------------------------------------------------
-- icon layout
----------------------------------------------------------------------

--- How many icons go in a row before wrapping. One setting for every bar in
--- the addon, so they stay visually consistent with each other.
function ns:PerRow()
	local n = FycoPvPDB and FycoPvPDB.perRow
	if type(n) == "number" and n >= 1 then return math.floor(n) end
	return 7
end

--- Lay `count` icons out from the anchor's TOPLEFT, wrapping to a new row
--- once PerRow of them are placed. Returns the width and height consumed, so
--- the caller can size its own frame and anything anchored below it.
---
--- Each icon keeps whatever size it already has rather than being told one.
--- That matters for the Dispel bar, which enlarges the buffs you can strip:
--- a row of mixed sizes still lines up, and the row's height follows its
--- tallest member instead of a number guessed in advance.
---
--- `vertical` flips the axes, so a bar set to grow downward wraps into a
--- second column instead of a second row.
function ns:LayoutIcons(anchor, icons, count, gap, perRow, vertical)
	perRow = math.max(1, perRow or ns:PerRow())
	gap = gap or 3

	local main, cross, crossSize, maxMain = 0, 0, 0, 0
	local placed = 0

	for i = 1, count do
		local f = icons[i]
		if f then
			local w, h = f:GetWidth() or 0, f:GetHeight() or 0

			if placed == perRow then
				cross = cross + crossSize + gap
				main, placed, crossSize = 0, 0, 0
			end

			f:ClearAllPoints()
			if vertical then
				f:SetPoint("TOPLEFT", anchor, "TOPLEFT", cross, -main)
				main = main + h + gap
				if w > crossSize then crossSize = w end
			else
				f:SetPoint("TOPLEFT", anchor, "TOPLEFT", main, -cross)
				main = main + w + gap
				if h > crossSize then crossSize = h end
			end

			if main - gap > maxMain then maxMain = main - gap end
			placed = placed + 1
		end
	end

	if vertical then
		return cross + crossSize, maxMain
	end
	return maxMain, cross + crossSize
end

----------------------------------------------------------------------
-- aura tooltips
----------------------------------------------------------------------

--- Which side of the icon the tooltip should open on, so it does not run off
--- the edge of the screen. GameTooltip does not reposition itself in 3.3.5a.
local function anchorFor(frame)
	local x = frame:GetCenter()
	local w = UIParent:GetWidth()
	if not x or not w then return "ANCHOR_RIGHT" end
	return (x > w / 2) and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

--- Give an aura icon Blizzard's own tooltip on hover -- the real spell text,
--- including the live "35 minutes remaining" line, because SetUnitBuff asks
--- the game rather than us.
---
--- The icon must keep `tipUnit`, `tipIndex` and `tipHarmful` current. They are
--- read at hover time rather than captured here, since these frames are
--- recycled between auras and a captured index would go stale the moment the
--- list reorders.
function ns:AuraTooltip(frame)
	frame:EnableMouse(true)

	frame:SetScript("OnEnter", function(self)
		if not (self.tipUnit and self.tipIndex) then return end
		if not UnitExists(self.tipUnit) then return end
		GameTooltip:SetOwner(self, anchorFor(self))
		if self.tipHarmful then
			GameTooltip:SetUnitDebuff(self.tipUnit, self.tipIndex)
		else
			GameTooltip:SetUnitBuff(self.tipUnit, self.tipIndex)
		end
		GameTooltip:Show()
	end)

	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

--- Re-read the tooltip if this icon is the one currently showing it. Called
--- from a module's update so the remaining-time line counts down while you
--- hover, which is what Blizzard's own frames do.
function ns:AuraTooltipRefresh(frame)
	if GameTooltip:IsOwned(frame) then
		local fn = frame:GetScript("OnEnter")
		if fn then fn(frame) end
	end
end

----------------------------------------------------------------------
-- unit registry
----------------------------------------------------------------------

--- Record what we know about a GUID. Later calls only fill in blanks, so a
--- weak source (combat log flags) never overwrites a strong one (a real token).
function ns:Learn(guid, name, class, utype, reaction)
	if not guid then return end
	local u = ns.units[guid]
	if not u then
		u = {}
		ns.units[guid] = u
	end
	u.name     = name     or u.name
	u.class    = class    or u.class
	u.utype    = utype    or u.utype
	u.reaction = reaction or u.reaction
	u.seen     = GetTime()
	return u
end

function ns:UnitType(guid)
	local u = ns.units[guid]
	return u and u.utype
end

--- Classify from combat log flags. This is the fallback that makes pet vs
--- player work even when nameplate healthbar colour cannot tell them apart.
local function typeFromFlags(flags)
	if not flags then return nil end
	if band(flags, TYPE_PLAYER) ~= 0 then return "player" end
	if band(flags, TYPE_PET) ~= 0 or band(flags, TYPE_GUARDIAN) ~= 0 then return "pet" end
	return "npc"
end
ns.TypeFromFlags = typeFromFlags

--- Hostile, friendly or neutral, from the same flag word. Cheap enough to run
--- on every combat log line, and it is what lets Archive separate the two
--- teams in a battleground.
local function reactionFromFlags(flags)
	if not flags then return nil end
	if band(flags, REACT_HOSTILE)  ~= 0 then return "hostile"  end
	if band(flags, REACT_FRIENDLY) ~= 0 then return "friendly" end
	if band(flags, REACT_NEUTRAL)  ~= 0 then return "neutral"  end
	return nil
end
ns.ReactionFromFlags = reactionFromFlags

----------------------------------------------------------------------
-- aura cache
----------------------------------------------------------------------

local function store(guid, spellID, duration, expires, stacks, mine, harmful, dtype)
	if not guid or not spellID then return end
	local a = ns.auras[guid]
	if not a then
		a = {}
		ns.auras[guid] = a
	end
	a[spellID] = {
		expires  = expires,
		duration = duration,
		stacks   = stacks or 0,
		mine     = mine,
		harmful  = harmful,
		dtype    = dtype,
	}
end
ns.StoreAura = store

----------------------------------------------------------------------
-- internal message bus, so modules do not each parse the combat log
----------------------------------------------------------------------

local subs = {}

function ns:Subscribe(msg, fn)
	if not subs[msg] then subs[msg] = {} end
	tinsert(subs[msg], fn)
end

function ns:Fire(msg, ...)
	local list = subs[msg]
	if not list then return end
	for i = 1, #list do
		list[i](...)
	end
end

----------------------------------------------------------------------
-- token-based scanning
----------------------------------------------------------------------

--- Full rescan of a unit we hold a token for. Authoritative: real durations.
function ns:ScanUnit(unit)
	if not UnitExists(unit) then return end
	local guid = UnitGUID(unit)
	if not guid then return end

	local _, class = UnitClass(unit)
	local utype
	if UnitIsPlayer(unit) then
		utype = "player"
	elseif UnitPlayerControlled(unit) then
		utype = "pet"
	else
		utype = "npc"
	end
	self:Learn(guid, UnitName(unit), class, utype)

	ns.auras[guid] = {}

	for i = 1, 40 do
		local name, _, _, count, _, duration, expires, caster, _, _, spellID = UnitBuff(unit, i)
		if not name then break end
		store(guid, spellID, duration, expires, count, caster == "player", false)
	end
	for i = 1, 40 do
		local name, _, _, count, dtype, duration, expires, caster, _, _, spellID = UnitDebuff(unit, i)
		if not name then break end
		store(guid, spellID, duration, expires, count, caster == "player", true, dtype)
	end
	return guid
end

--- What we believe is on a GUID right now, expiry-filtered.
function ns:GetAura(guid, spellID)
	local a = ns.auras[guid]
	local e = a and a[spellID]
	if not e then return nil end
	if e.expires and e.expires > 0 and e.expires < GetTime() then
		a[spellID] = nil
		return nil
	end
	return e
end

----------------------------------------------------------------------
-- combat log -> registry + cache
----------------------------------------------------------------------

-- 3.3.5a signature: timestamp, event, srcGUID, srcName, srcFlags,
--                   dstGUID, dstName, dstFlags, then event-specific args.
ns:On("COMBAT_LOG_EVENT_UNFILTERED", function(_, _, ev, srcGUID, srcName, srcFlags,
                                              dstGUID, dstName, dstFlags, ...)
	if srcGUID then
		ns:Learn(srcGUID, srcName, nil, typeFromFlags(srcFlags), reactionFromFlags(srcFlags))
	end
	if dstGUID then
		ns:Learn(dstGUID, dstName, nil, typeFromFlags(dstFlags), reactionFromFlags(dstFlags))
	end

	if ev == "SPELL_AURA_APPLIED" or ev == "SPELL_AURA_REFRESH"
	   or ev == "SPELL_AURA_APPLIED_DOSE" then
		local spellID, _, _, auraType, amount = ...
		if not spellID then return end
		local def = ns.Defensives[spellID]
		local dur = (def and def.dur and def.dur > 0) and def.dur or 0
		local now = GetTime()
		store(dstGUID, spellID, dur, dur > 0 and (now + dur) or 0, amount,
		      srcGUID == ns.player, auraType == "DEBUFF")
		ns:Fire("AuraApplied", dstGUID, spellID, srcGUID, auraType, dstFlags)

	elseif ev == "SPELL_AURA_REMOVED" then
		local spellID = ...
		if spellID and ns.auras[dstGUID] then
			ns.auras[dstGUID][spellID] = nil
		end
		ns:Fire("AuraRemoved", dstGUID, spellID, srcGUID)

	elseif ev == "SPELL_CAST_SUCCESS" then
		local spellID = ...
		ns:Fire("CastSuccess", srcGUID, spellID, dstGUID)

	elseif ev == "SPELL_INTERRUPT" then
		-- spellID/name/school describe the KICK; the extra* trio describe the
		-- spell that got cut. The school of the interrupted spell is the one
		-- that gets locked out, which is why Lockout reads extraSchool.
		local spellID, _, _, extraID, _, extraSchool = ...
		ns:Fire("Interrupt", srcGUID, dstGUID, spellID, extraID, extraSchool)

	elseif ev == "SPELL_DISPEL" or ev == "SPELL_STOLEN" then
		local spellID, _, _, extraID, _, _, auraType = ...
		ns:Fire("Dispel", srcGUID, dstGUID, spellID, extraID, auraType,
		        ev == "SPELL_STOLEN")

	elseif ev == "UNIT_DIED" or ev == "PARTY_KILL" then
		ns.auras[dstGUID] = nil
		ns:Fire("Death", dstGUID, srcGUID, ev == "PARTY_KILL")
	end
end)

----------------------------------------------------------------------
-- match boundaries
----------------------------------------------------------------------

-- Everything that accumulates per opponent -- diminishing returns, enemy
-- cooldowns, inferred specs, the name->GUID map -- is worthless once the
-- match ends, and actively harmful if it survives: a stale GUID under a name
-- you meet again next game resolves to a unit that no longer exists. So one
-- signal, MatchStart, wipes the lot. Modules subscribe rather than each
-- working out for itself where a match begins.
local lastInstance

local function CheckMatch()
	local _, itype = IsInInstance()
	itype = itype or "none"
	if itype == ns.instanceType then return end
	local prev = ns.instanceType
	ns.instanceType = itype
	if itype == "arena" or itype == "pvp" then
		ns:Fire("MatchStart", itype)
		ns:Print(itype == "arena" and "|cff00ff00arena|r - trackers reset"
		                           or "|cff00ff00battleground|r - trackers reset")
	elseif prev == "arena" or prev == "pvp" then
		ns:Fire("MatchEnd", prev)
	end
end

ns:On("PLAYER_ENTERING_WORLD", CheckMatch)
ns:On("ZONE_CHANGED_NEW_AREA", CheckMatch)

function ns:InArena() return ns.instanceType == "arena" end
function ns:InBG()    return ns.instanceType == "pvp" end
function ns:InPvP()   return ns.instanceType == "arena" or ns.instanceType == "pvp" end

-- Core's own share of the reset: drop every cached unit and aura, then put
-- the player straight back, since half the addon looks itself up by GUID.
ns:Subscribe("MatchStart", function()
	ns.units, ns.auras = {}, {}
	if ns.player then
		local _, class = UnitClass("player")
		ns:Learn(ns.player, UnitName("player"), class, "player")
	end
end)

----------------------------------------------------------------------
-- token-based rescans
----------------------------------------------------------------------

ns:On("PLAYER_TARGET_CHANGED", function() ns:ScanUnit("target") end)
ns:On("PLAYER_FOCUS_CHANGED",  function() ns:ScanUnit("focus") end)
ns:On("UPDATE_MOUSEOVER_UNIT", function() ns:ScanUnit("mouseover") end)
ns:On("UNIT_AURA", function(_, unit)
	if unit == "player" or unit == "target" or unit == "focus" then
		ns:ScanUnit(unit)
		ns:Fire("UnitAura", unit)
	end
end)

----------------------------------------------------------------------
-- module registry
----------------------------------------------------------------------

ns.modules = {}

--- Is this module switched on right now? Modules call this every frame rather
--- than only at load, so the checkboxes take effect immediately.
function ns:Enabled(name)
	return FycoPvPDB and FycoPvPDB.enabled and FycoPvPDB.enabled[name] ~= false
end

function ns:Module(name)
	local m = { name = name }
	ns.modules[name] = m
	return m
end

----------------------------------------------------------------------
-- saved variables + login
----------------------------------------------------------------------

local defaults = {
	sounds = true,
	debug  = false,
	-- icons per row before a bar wraps. One number for every bar, so they
	-- stay consistent with each other rather than each drifting on its own.
	perRow = 7,
}

ns:On("PLAYER_LOGIN", function()
	FycoPvPDB = FycoPvPDB or {}
	for k, v in pairs(defaults) do
		if FycoPvPDB[k] == nil then FycoPvPDB[k] = v end
	end
	FycoPvPDB.enabled = FycoPvPDB.enabled or {}
	-- Default state for every module. Written one key at a time rather than
	-- replacing the table, so a module added in a later version switches
	-- itself on without resetting the choices already saved.
	local modDefaults = {
		control = true, procs = true, casts = true, auras = true, alerts = true,
		cooldowns = true, plates = true, options = true, bar = true, buffs = true,
		logger = true, recap = true, spec = true, range = true, lockout = true,
		stats = true, announce = true, archive = true, dispel = true,
		cdtext = true,
	}
	for k, v in pairs(modDefaults) do
		if FycoPvPDB.enabled[k] == nil then FycoPvPDB.enabled[k] = v end
	end

	ns.player = UnitGUID("player")
	local _, class = UnitClass("player")
	ns:Learn(ns.player, UnitName("player"), class, "player")

	-- Each OnLoad runs inside a pcall, for the same reason the ticker does.
	-- pairs() order is unspecified, so an error thrown by ONE module used to
	-- abort this whole handler and take every module not yet reached with it --
	-- including Options, so the addon vanished from Interface -> AddOns and
	-- looked like it had failed to load at all. One broken module should cost
	-- you that module, and say so, rather than the entire addon in silence.
	for name, m in pairs(ns.modules) do
		-- Everything loads. Each module checks ns:Enabled itself each frame, so
		-- turning one off takes effect at once instead of needing a reload.
		-- Plates is the exception: it rewrites Blizzard's plate regions, and
		-- undoing that cleanly at runtime is not worth the complexity.
		if m.OnLoad and (name ~= "plates" or FycoPvPDB.enabled[name] ~= false) then
			local ok, err = pcall(m.OnLoad, m)
			if ok then
				ns:Debug("module loaded:", name)
			else
				-- loud, not silent: a module that is not there is something you
				-- need to know about, and the message names the culprit
				ns:Print("|cffff4444module '" .. name .. "' failed to load:|r "
				      .. tostring(err))
			end
		end
	end

	ns:Print("v" .. (GetAddOnMetadata(ADDON, "Version") or "?") ..
	         " loaded. |cffffff00/fyco|r for commands.")
end)

-- prune stale cache entries so a long battleground does not grow unbounded
ns:OnTick(function(now)
	if ns._sweep and now - ns._sweep <= 5 then return end
	ns._sweep = now
	for guid, auras in pairs(ns.auras) do
		for id, a in pairs(auras) do
			if a.expires and a.expires > 0 and a.expires < now then
				auras[id] = nil
			end
		end
	end
	for guid, u in pairs(ns.units) do
		if u.seen and now - u.seen > 300 then
			ns.units[guid] = nil
			ns.auras[guid] = nil
		end
	end
end)

----------------------------------------------------------------------
-- slash
----------------------------------------------------------------------

SLASH_FYCOPVP1 = "/fyco"
SLASH_FYCOPVP2 = "/fycopvp"

SlashCmdList.FYCOPVP = function(input)
	local cmd, rest = (input or ""):match("^(%S*)%s*(.-)%s*$")
	cmd  = (cmd or ""):lower()
	rest = rest or ""

	if cmd == "voices" then
		-- walk the voice pack so a missing or silent file is obvious
		local ids, i, elapsed = {}, 0, 0
		for id in pairs(ns.Voice) do tinsert(ids, id) end
		table.sort(ids)
		ns:Print("playing " .. #ids .. " voice lines, one per 1.2s. |cffffff00/fyco stop|r to cut it short.")
		local f = CreateFrame("Frame")
		ns._auditionFrame = f
		f:SetScript("OnUpdate", function(self, e)
			elapsed = elapsed + e
			if elapsed < 1.2 then return end
			elapsed = 0
			i = i + 1
			if i > #ids then self:SetScript("OnUpdate", nil) ns:Print("voice pack done") return end
			local id = ids[i]
			ns:Print(string.format("  %s (%d) -> %s", tostring(GetSpellInfo(id) or "?"), id, ns.Voice[id]))
			PlaySoundFile(ns.VoiceDir .. ns.Voice[id] .. ".mp3")
		end)

	elseif cmd == "procs" then
		if ns.ProcDemo then ns:ProcDemo() else ns:Print("procs module is off") end

	elseif cmd == "stop" then
		if ns._auditionFrame then ns._auditionFrame:SetScript("OnUpdate", nil) end
		if ns._procDemoFrame then ns._procDemoFrame:SetScript("OnUpdate", nil) end
		ns:Print("stopped")

	elseif cmd == "sounds" then
		ns:Print("playing every fallback cue, one per second:")
		local keys, i, elapsed = {}, 0, 0
		for k in pairs(ns.Sounds) do tinsert(keys, k) end
		table.sort(keys)
		local f = CreateFrame("Frame")
		f:SetScript("OnUpdate", function(self, e)
			elapsed = elapsed + e
			if elapsed < 1 then return end
			elapsed = 0
			i = i + 1
			if i > #keys then self:SetScript("OnUpdate", nil) return end
			ns:Print("  " .. keys[i] .. " -> " .. ns.Sounds[keys[i]])
			PlaySoundFile(ns.Sounds[keys[i]])
		end)

	elseif cmd == "sound" then
		FycoPvPDB.sounds = not FycoPvPDB.sounds
		ns:Print("sounds", FycoPvPDB.sounds and "|cff00ff00on|r" or "|cffff0000off|r")

	elseif cmd == "debug" then
		FycoPvPDB.debug = not FycoPvPDB.debug
		ns:Print("debug", FycoPvPDB.debug and "on" or "off")

	elseif cmd == "status" then
		local nu, na = 0, 0
		for _ in pairs(ns.units) do nu = nu + 1 end
		for _ in pairs(ns.auras) do na = na + 1 end
		ns:Print("units cached:", nu, "| units with auras:", na)
		for name in pairs(ns.modules) do
			ns:Print("  module", name, FycoPvPDB.enabled[name] ~= false and "on" or "off")
		end

	elseif cmd == "pos" then
		-- /fyco pos target 758.3 263.3   (same anchor and numbers MoveAnything uses)
		local unit, x, y = rest:match("^(%a+)%s+(-?[%d%.]+)%s+(-?[%d%.]+)$")
		if not unit then
			ns:Print("usage: |cffffff00/fyco pos <player|target|focus> <x> <y>|r")
			ns:Print("x and y are measured from the bottom-left of the screen,")
			ns:Print("the same as the numbers MoveAnything shows. Current:")
			if ns.CastBarInfo then ns:CastBarInfo() end
		elseif ns.SetCastBarPos and ns:SetCastBarPos(unit:lower(), tonumber(x), tonumber(y)) then
			ns:Print(string.format("%s cast bar -> x=%s y=%s", unit, x, y))
		else
			ns:Print("no such bar: " .. unit .. " (use player, target or focus)")
		end

	elseif cmd == "scale" then
		local unit, s = rest:match("^(%a+)%s+([%d%.]+)$")
		if not unit then
			ns:Print("usage: |cffffff00/fyco scale <player|target|focus> <number>|r")
		elseif ns.SetCastBarScale and ns:SetCastBarScale(unit:lower(), tonumber(s)) then
			ns:Print(string.format("%s cast bar scale -> %s", unit, s))
		else
			ns:Print("no such bar: " .. unit)
		end

	elseif cmd == "blizz" then
		FycoPvPDB.hideBlizzCast = not FycoPvPDB.hideBlizzCast
		ns:Print("blizzard cast bars",
			FycoPvPDB.hideBlizzCast and "|cffff0000hidden|r" or "|cff00ff00shown|r",
			"- |cffffff00/reload|r to apply")

	elseif cmd == "lock" then
		ns:Fire("ToggleLock")

	elseif cmd == "track" then
		if rest == "" then
			ns:Print("tracked cooldowns (|cffffff00/fyco track <spell>|r to add):")
			if ns.BarList then ns:BarList() end
		elseif ns.BarAdd then
			local ok, msg = ns:BarAdd(rest)
			ns:Print(ok and ("tracking " .. msg) or ("could not add: " .. tostring(msg)))
		end

	elseif cmd == "buff" then
		if rest == "" then
			ns:Print("watched buffs (|cffffff00/fyco buff <name>|r to add):")
			if ns.BuffList then ns:BuffList() end
		elseif ns.BuffAdd then
			local ok, msg = ns:BuffAdd(rest)
			ns:Print(ok and ("watching " .. msg) or ("could not add: " .. tostring(msg)))
		end

	elseif cmd == "unbuff" then
		local n = tonumber(rest)
		if n and ns.BuffRemove then
			local ok, msg = ns:BuffRemove(n)
			ns:Print(ok and ("stopped watching " .. msg) or "no entry with that number")
		else
			ns:Print("usage: |cffffff00/fyco unbuff <number>|r - see |cffffff00/fyco buff|r")
		end

	elseif cmd == "untrack" then
		local n = tonumber(rest)
		if n and ns.BarRemove then
			local ok, msg = ns:BarRemove(n)
			ns:Print(ok and ("stopped tracking " .. msg) or "no entry with that number")
		else
			ns:Print("usage: |cffffff00/fyco untrack <number>|r - see |cffffff00/fyco track|r")
		end

	elseif cmd == "voice" then
		-- /fyco voice            list the lines flagged as wrong-language
		-- /fyco voice 42292 Trinket   point a spell at a different file
		local id, file = rest:match("^(%d+)%s+(%S+)$")
		if id then
			FycoPvPDB.voiceOverride = FycoPvPDB.voiceOverride or {}
			FycoPvPDB.voiceOverride[tonumber(id)] = file
			ns:Print(string.format("%s -> %s.mp3", GetSpellInfo(tonumber(id)) or id, file))
			PlaySoundFile(ns.VoiceDir .. file .. ".mp3")
		else
			ns:Print("voice lines from the Russian pack (swap with |cffffff00/fyco voice <spellID> <file>|r):")
			local seen = {}
			for sid, f in pairs(ns.Voice) do
				if ns.VoiceSuspect[f] and not seen[f] then
					seen[f] = true
					ns:Print(string.format("  %-16s %s (%d)", f, GetSpellInfo(sid) or "?", sid))
				end
			end
			for sid, f in pairs(FycoPvPDB.voiceOverride or {}) do
				ns:Print(string.format("  |cff00ff00override|r %d -> %s", sid, f))
			end
		end

	elseif cmd == "plates" then
		if ns.PlatesConfig then ns:PlatesConfig(rest) else ns:Print("plates module is off") end

	elseif cmd == "auras" then
		if ns.AuraDebug then ns:AuraDebug() else ns:Print("plates module is off") end

	elseif cmd == "debuffs" then
		if ns.DebuffConfig then ns:DebuffConfig(rest)
		else ns:Print("auras module is off") end

	elseif cmd == "cds" then
		if ns.CDReport then ns:CDReport() else ns:Print("cooldowns module is off") end

	elseif cmd == "log" then
		if ns.LogReport then ns:LogReport() else ns:Print("logger module is off") end

	elseif cmd == "recap" then
		-- "now" shows the window as it stands, for testing without dying
		if ns.RecapReport then ns:RecapReport(rest:lower() == "now")
		else ns:Print("recap module is off") end

	elseif cmd == "games" then
		if not ns.GamesList then
			ns:Print("archive module is off")
		elseif rest:lower() == "clear" then
			ns:GamesClear()
		else
			ns:GamesList()
		end

	elseif cmd == "game" then
		local n = tonumber(rest)
		if not ns.GameReport then
			ns:Print("archive module is off")
		elseif n then
			ns:GameReport(n)
		else
			ns:Print("usage: |cffffff00/fyco game <number>|r - see |cffffff00/fyco games|r")
		end

	elseif cmd == "spec" then
		if ns.SpecReport then ns:SpecReport() else ns:Print("spec module is off") end

	elseif cmd == "drink" then
		if ns.DrinkDebug then ns:DrinkDebug() else ns:Print("spec module is off") end

	elseif cmd == "dispel" then
		if ns.DispelConfig then ns:DispelConfig(rest)
		else ns:Print("dispel module is off") end

	elseif cmd == "cdtext" then
		if ns.CDTextConfig then ns:CDTextConfig(rest)
		else ns:Print("cooldown text module is off") end

	elseif cmd == "perrow" then
		local n = tonumber(rest)
		if n and n >= 1 and n <= 20 then
			FycoPvPDB.perRow = math.floor(n)
			ns:Print("bars now wrap after |cffffff00" .. FycoPvPDB.perRow
			      .. "|r icons. Rows that are laid out once need a "
			      .. "|cffffff00/reload|r; the rest change as they refresh.")
		else
			ns:Print("icons per row before a bar wraps: |cffffff00"
			      .. ns:PerRow() .. "|r")
			ns:Print("usage: |cffffff00/fyco perrow <1-20>|r - applies to every bar")
		end

	elseif cmd == "range" then
		if ns.RangeConfig then ns:RangeConfig(rest) else ns:Print("range module is off") end

	elseif cmd == "announce" then
		if ns.AnnounceConfig then ns:AnnounceConfig(rest)
		else ns:Print("announce module is off") end

	elseif cmd == "stats" then
		if not ns.StatsReport then
			ns:Print("stats module is off")
		elseif rest:lower():match("^reset") then
			ns:StatsReset(rest:lower():match("all") ~= nil)
		elseif rest:lower():match("^help") then
			ns:StatsHelp()
		else
			ns:StatsReport()
		end

	elseif cmd == "" or cmd == "config" or cmd == "options" then
		if ns.OpenOptions then ns.OpenOptions() else ns:Print("options module is off") end
		ns:Print("commands: |cffffff00/fyco help|r")

	else
		ns:Print("commands:")
		ns:Print("  |cffffff00/fyco status|r - cache and module state")
		ns:Print("  |cffffff00/fyco voices|r - audition the voice pack (|cffffff00/fyco stop|r to halt)")
		ns:Print("  |cffffff00/fyco procs|r  - preview each proc overlay in turn")
		ns:Print("  |cffffff00/fyco sounds|r - play every fallback cue")
		ns:Print("  |cffffff00/fyco sound|r  - toggle sounds")
		ns:Print("  |cffffff00/fyco lock|r   - toggle frame dragging")
		ns:Print("  |cffffff00/fyco perrow|r - icons per row before a bar wraps")
		ns:Print("  |cffffff00/fyco pos|r    - place a cast bar by MoveAnything coordinates")
		ns:Print("  |cffffff00/fyco scale|r  - resize a cast bar")
		ns:Print("  |cffffff00/fyco blizz|r  - toggle blizzard's own cast bars")
		ns:Print("  |cffffff00/fyco recap|r  - replay your last death (|cffffff00recap now|r = live window)")
		ns:Print("  |cffffff00/fyco games|r  - every arena and BG recorded, newest last")
		ns:Print("  |cffffff00/fyco game N|r - the full report for one of them")
		ns:Print("  |cffffff00/fyco stats|r  - match / session / lifetime counters")
		ns:Print("  |cffffff00/fyco stats reset|r - end the session now (|cffffff00reset all|r wipes lifetime)")
		ns:Print("  |cffffff00/fyco spec|r   - who we think is what, and how sure")
		ns:Print("  |cffffff00/fyco range|r  - which spell the range check uses")
		ns:Print("  |cffffff00/fyco announce|r - party announce on/off and channel")
		ns:Print("  |cffffff00/fyco dispel|r - which enemy buff types to track")
		ns:Print("  |cffffff00/fyco cdtext|r - cooldown numbers on your action bars")
		ns:Print("  |cffffff00/fyco drink|r  - dump enemy buffs, to fix drink detection")
		ns:Print("  |cffffff00/fyco log|r    - what the logger has measured so far")
		ns:Print("  |cffffff00/fyco cds|r    - enemy cooldowns corrected against the table")
		ns:Print("  |cffffff00/fyco debuffs|r- show every debuff, or only your own")
		ns:Print("  |cffffff00/fyco auras|r  - why the target's plate shows what it shows")
		ns:Print("  |cffffff00/fyco plates|r - pet/npc nameplate scale and alpha")
		ns:Print("  |cffffff00/fyco track|r  - your own cooldown bar (add/list)")
		ns:Print("  |cffffff00/fyco untrack|r- remove one by number")
		ns:Print("  |cffffff00/fyco buff|r   - missing-buff watch list")
		ns:Print("  |cffffff00/fyco unbuff|r - remove one by number")
		ns:Print("  |cffffff00/fyco voice|r  - list or swap voice lines")
		ns:Print("  |cffffff00/fyco|r        - open the options panel")
		ns:Print("  |cffffff00/fyco debug|r  - toggle debug output")
	end
end
