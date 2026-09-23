--[[ FycoPvP - Modules/Spec.lua
     Works out what an enemy actually IS from what they cast, and marks healers.

     3.3.5a exposes no spec information for anyone but yourself, and hostile
     inspection is blocked, so this is inference, not fact. A Priest who casts
     Penance is Discipline; a Priest who has cast nothing is just a Priest.
     Every reading carries that distinction: until a signature spell has been
     seen, nothing is claimed at all.

     Confidence rises with corroboration. One signature spell is enough to
     display, but the spec with the most sightings wins, so a Holy paladin who
     taps Crusader Strike once does not get relabelled Retribution.

     Also flags drinking, which is the other thing worth knowing about an
     enemy and which arrives through the same aura plumbing.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("spec")

local GetTime      = GetTime
local GetSpellInfo = GetSpellInfo
local UnitExists   = UnitExists
local UnitGUID     = UnitGUID
local UnitBuff     = UnitBuff
local UnitName     = UnitName

-- [guid] = { class, spec, role, hits = {[classspec] = count}, count, at }
local known = {}
-- [name] = the same record. Nameplates only ever see a name, so we mirror it.
local byName = {}
-- [guid] = time until which we stay quiet about this one drinking
local drinking = {}

----------------------------------------------------------------------
-- inference
----------------------------------------------------------------------

-- How many sightings before a healer is called out loud. One is not enough:
-- the display can afford to be provisional, but a name printed into your chat
-- frame cannot be taken back, so that one wants corroboration.
local ANNOUNCE_MIN = 2

--- Credit a spell to the unit that CAST it. Never to the unit it landed on --
--- see the AuraApplied subscriber for why that distinction matters.
local function Note(guid, spellID)
	if not guid or not spellID or guid == ns.player then return end
	local name = GetSpellInfo(spellID)
	local hit  = name and ns.SpecSpells[name]
	if not hit then return end

	local u = ns.units[guid]
	-- pets cast plenty of things; a Felhunter is not a Demonology warlock
	if u and u.utype and u.utype ~= "player" then return end

	-- A class read off a real unit token outranks any inference we can make.
	-- A warrior is not a Discipline priest however many of their shields land
	-- on him, so a sighting that contradicts a known class is discarded rather
	-- than allowed to accumulate.
	if u and u.class and u.class ~= hit.class then return end

	local rec = known[guid]
	if not rec then
		rec = { hits = {} }
		known[guid] = rec
	end

	local key = hit.class .. hit.spec
	rec.hits[key] = (rec.hits[key] or 0) + 1
	rec.at = GetTime()

	-- Take the spec with the most evidence behind it, not simply the newest.
	-- Ties break on the key so the winner is stable: pairs() order is
	-- unspecified and rehashes on insert, and without this a dead heat could
	-- flip the displayed spec back and forth between equal scores.
	local bestKey, bestN
	for k, n in pairs(rec.hits) do
		if not bestN or n > bestN or (n == bestN and k < bestKey) then
			bestKey, bestN = k, n
		end
	end
	if bestKey ~= key then return end

	local changed = (rec.spec ~= hit.spec)
	rec.class, rec.spec, rec.role = hit.class, hit.spec, hit.role
	rec.count = bestN

	if u and u.name then
		byName[u.name:match("^([^-]+)") or u.name] = rec
	end

	if changed then
		rec.announced = nil        -- a new reading earns a new announcement
		ns:Fire("SpecLearned", guid, rec)
	end

	if rec.role == "healer" and not rec.announced
	   and rec.count >= ANNOUNCE_MIN
	   and FycoPvPDB.specAnnounceHealer and u and u.name then
		rec.announced = true
		ns:Print(string.format("|cff20ff50healer:|r %s (%s %s)",
			u.name, rec.spec, hit.class:lower()))
	end
end

--- What we believe this GUID is. nil when we have seen nothing to go on.
function ns:GetSpec(guid)
	return guid and known[guid] or nil
end

--- Same, by the bare name a nameplate shows.
function ns:GetSpecByName(name)
	return name and byName[name] or nil
end

function ns:IsHealer(guid)
	local r = guid and known[guid]
	return (r and r.role == "healer") or false
end

----------------------------------------------------------------------
-- drinking
----------------------------------------------------------------------

local function CallDrink(guid, name)
	if not FycoPvPDB.drinkAlert then return end
	-- Arena-only by default: in a battleground somebody is always drinking,
	-- and the call becomes noise rather than information.
	if FycoPvPDB.drinkArenaOnly and not ns:InArena() then return end
	if not guid then return end

	local now = GetTime()
	if drinking[guid] and now < drinking[guid] then return end
	drinking[guid] = now + 20

	ns:Print(string.format("|cff40c0ff%s is drinking|r", name or "an enemy"))
	if FycoPvPDB.drinkSound then ns:Sound("interrupt", 3) end
	ns:Fire("Drinking", guid, name)
end

--- Arena tokens are the reliable path: a drink taken out of combat may never
--- reach your combat log, but the aura is right there on arena1..5.
local function ScanArenaDrinks()
	if not FycoPvPDB.drinkAlert or not ns:InArena() then return end
	for i = 1, 5 do
		local unit = "arena" .. i
		if UnitExists(unit) then
			for j = 1, 10 do
				local bname = UnitBuff(unit, j)
				if not bname then break end
				if ns.DrinkAuras[bname] then
					CallDrink(UnitGUID(unit), UnitName(unit))
					break
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- reporting
----------------------------------------------------------------------

--- /fyco spec -- what we think everyone is, and how sure we are.
function ns:SpecReport()
	local rows = 0
	ns:Print("inferred specs (deduced from spells seen cast, not from the API):")
	for guid, rec in pairs(known) do
		local u = ns.units[guid]
		if rec.spec then
			local c = ns.RoleColor[rec.role] or { 1, 1, 1 }
			ns:Print(string.format("  %-16s |cff%02x%02x%02x%s %s|r |cff808080x%d|r%s",
				(u and u.name) or "?",
				c[1] * 255, c[2] * 255, c[3] * 255,
				rec.spec, (rec.class or ""):lower(), rec.count or 1,
				rec.role == "healer" and "  |cff20ff50HEALER|r" or ""))
			rows = rows + 1
		end
	end
	if rows == 0 then
		ns:Print("  nobody identified yet - specs are learned from signature casts")
	end
end

--- /fyco drink -- print what the enemy actually has on them, so the name list
--- in Data.lua can be corrected if this core calls the aura something else.
local function DumpBuffs(unit)
	ns:Print("buffs on " .. (UnitName(unit) or unit) .. ":")
	for j = 1, 16 do
		local bname = UnitBuff(unit, j)
		if not bname then break end
		ns:Print(string.format("  %s%s", bname,
			ns.DrinkAuras[bname] and "  |cff00ff00<- matched as drinking|r" or ""))
	end
end

function ns:DrinkDebug()
	local any = false
	for i = 1, 5 do
		local unit = "arena" .. i
		if UnitExists(unit) then
			any = true
			DumpBuffs(unit)
		end
	end
	if not any then
		if UnitExists("target") then
			ns:Print("no arena units, showing your target instead:")
			DumpBuffs("target")
		else
			ns:Print("no arena units and no target - nothing to inspect")
		end
	end
end

----------------------------------------------------------------------

function M:OnLoad()
	if FycoPvPDB.drinkAlert     == nil then FycoPvPDB.drinkAlert     = true  end
	if FycoPvPDB.drinkArenaOnly == nil then FycoPvPDB.drinkArenaOnly = true  end
	if FycoPvPDB.drinkSound     == nil then FycoPvPDB.drinkSound     = false end
	if FycoPvPDB.specAnnounceHealer == nil then FycoPvPDB.specAnnounceHealer = true end

	ns:Subscribe("CastSuccess", function(srcGUID, spellID)
		if ns:Enabled("spec") then Note(srcGUID, spellID) end
	end)

	-- Some signatures never appear as a cast: Shadowform and Moonkin Form show
	-- up only as the aura they leave behind. Those are SELF buffs, so the
	-- caster and the target are the same unit and crediting the caster already
	-- catches them.
	--
	-- Only the caster is ever credited. An earlier version also credited the
	-- unit the aura landed ON, which flagged whoever a healer touched as a
	-- healer themselves -- Divine Aegis, Power Infusion, Prayer of Mending,
	-- Earth Shield, Beacon of Light and Riptide all land on a teammate, so one
	-- shield on a warrior was enough to announce him as a priest.
	ns:Subscribe("AuraApplied", function(dstGUID, spellID, srcGUID)
		if not ns:Enabled("spec") then return end
		Note(srcGUID, spellID)

		local n = spellID and GetSpellInfo(spellID)
		if n and ns.DrinkAuras[n] and dstGUID and dstGUID ~= ns.player then
			local u = ns.units[dstGUID]
			CallDrink(dstGUID, u and u.name)
		end
	end)

	-- Arena drink polling at 1Hz rather than the shared 10Hz: nobody needs to
	-- know within a tenth of a second that a healer sat down.
	local acc = 0
	ns:OnTick(function(now)
		if not ns:Enabled("spec") then return end
		if now - acc < 1 then return end
		acc = now
		ScanArenaDrinks()
	end)

	ns:Subscribe("MatchStart", function()
		known, byName, drinking = {}, {}, {}
	end)
end
