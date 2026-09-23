--[[ FycoPvP - Modules/Logger.lua
     Step 0 support. The combat log reports spell IDs but never durations or
     cooldowns, so the tables in Data.lua are currently retail assumptions.
     This module measures the real values on Frostmourne by timing each aura
     from APPLIED to REMOVED, and each repeat cast of a tracked cooldown.
     Writes FycoPvPLog (per character). Throwaway: it comes out once the
     tables are confirmed. Loaded by Core.lua at PLAYER_LOGIN.               ]]

local ADDON, ns = ...
local M = ns:Module("logger")

local GetTime = GetTime
local MAX_SAMPLES = 12

local pending  = {}   -- [guid][spellID] = applied-at timestamp
local lastCast = {}   -- [guid][spellID] = last cast timestamp, for cooldown gaps

local function Log()
	FycoPvPLog = FycoPvPLog or {}
	FycoPvPLog.auras = FycoPvPLog.auras or {}
	FycoPvPLog.cds   = FycoPvPLog.cds   or {}
	FycoPvPLog.seen  = FycoPvPLog.seen  or {}
	return FycoPvPLog
end

local function round2(v)
	return tonumber(string.format("%.2f", v))
end

local function sample(bucket, spellID, name, value, key)
	local L = Log()
	local t = L[bucket][spellID]
	if not t then
		t = { name = name, n = 0 }
		t[key] = {}
		L[bucket][spellID] = t
	end
	t.name = t.name or name
	t.n = t.n + 1
	if #t[key] < MAX_SAMPLES then
		table.insert(t[key], round2(value))
	end
	if not t.min or value < t.min then t.min = round2(value) end
	if not t.max or value > t.max then t.max = round2(value) end
end

----------------------------------------------------------------------

function M:OnLoad()
	local L = Log()
	L.asof = date("%Y-%m-%d")

	-- Build name -> ids once, so we can spot a spell whose aura ID differs from
	-- the one we track. That is exactly how Spell Reflection went unnoticed:
	-- warriors cast 23920 but the buff that lands is 59725 or 36096.
	local byName = {}
	for id, info in pairs(ns.Defensives) do
		local n = info.name
		if n then byName[n] = byName[n] or {} ; table.insert(byName[n], id) end
	end
	L.idMismatch = L.idMismatch or {}

	ns:Subscribe("AuraApplied", function(guid, spellID)
		if not guid or not spellID then return end
		if not ns.Defensives[spellID] then
			local n = GetSpellInfo(spellID)
			if n and byName[n] then
				L.idMismatch[spellID] = n .. " (table has " .. table.concat(byName[n], ",") .. ")"
			end
		end
		-- only measure what we need to get right; note everything else by name
		if not (ns.Defensives[spellID] or ns.CC[spellID]) then
			L.seen[spellID] = L.seen[spellID] or (GetSpellInfo(spellID) or "?")
			return
		end
		pending[guid] = pending[guid] or {}
		pending[guid][spellID] = GetTime()
	end)

	ns:Subscribe("AuraRemoved", function(guid, spellID)
		local p = guid and pending[guid]
		local t0 = p and spellID and p[spellID]
		if not t0 then return end
		p[spellID] = nil
		local observed = GetTime() - t0
		-- drop dispels and early breaks: shorter than anything real we track,
		-- and they would drag the minimum down and make it look wrong
		if observed < 0.4 or observed > 400 then return end
		sample("auras", spellID, GetSpellInfo(spellID), observed, "dur")
	end)

	ns:Subscribe("CastSuccess", function(srcGUID, spellID)
		if not srcGUID or not spellID then return end
		if not (ns.Defensives[spellID] or ns.Interrupts[spellID]) then return end
		lastCast[srcGUID] = lastCast[srcGUID] or {}
		local prev = lastCast[srcGUID][spellID]
		local now  = GetTime()
		lastCast[srcGUID][spellID] = now
		if prev then
			local gap = now - prev
			if gap > 1 and gap < 700 then
				sample("cds", spellID, GetSpellInfo(spellID), gap, "gap")
			end
		end
	end)

	ns:Print("|cff808080logger recording - /fyco log to summarise|r")
end

----------------------------------------------------------------------
-- reporting
----------------------------------------------------------------------

--- Print what has been measured, and flag anything that disagrees with Data.lua.
function ns:LogReport()
	local L = Log()
	local rows = 0

	ns:Print("measured aura durations (observed vs Data.lua):")
	for spellID, t in pairs(L.auras) do
		local def = ns.Defensives[spellID]
		local expected = def and def.dur
		local flag = ""
		if expected and expected > 0 and t.max then
			-- compare against the longest clean sample: short ones are breaks
			if math.abs(t.max - expected) > 0.6 then flag = " |cffff4444MISMATCH|r" end
		end
		ns:Print(string.format("  %s (%d) n=%d min=%.1f max=%.1f expected=%s%s",
			tostring(t.name), spellID, t.n, t.min or 0, t.max or 0,
			expected and tostring(expected) or "-", flag))
		rows = rows + 1
	end
	if rows == 0 then ns:Print("  nothing recorded yet - go fight someone") end

	local mism = 0
	for sid, what in pairs(L.idMismatch or {}) do
		if mism == 0 then ns:Print("|cffff4444aura IDs we are NOT tracking but should be:|r") end
		ns:Print(string.format("  %d -> %s", sid, what))
		mism = mism + 1
	end

	local cds = 0
	for spellID, t in pairs(L.cds) do
		if cds == 0 then ns:Print("observed cooldown gaps (the minimum approaches the real cooldown):") end
		ns:Print(string.format("  %s (%d) n=%d min=%.1f",
			tostring(t.name), spellID, t.n, t.min or 0))
		cds = cds + 1
	end
end
