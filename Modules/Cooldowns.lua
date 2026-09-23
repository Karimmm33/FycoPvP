--[[ FycoPvP - Modules/Cooldowns.lua
     Step 6. Two trackers that both answer "what can they still do to me, and
     what can I still land on them".

       DR  - diminishing returns per target, per category. Answers the question
             that started this: how long until Fear is back to full on this guy.
             Level rises on each application inside the window; the window
             reopens ns.DR_RESET seconds after the aura FADES, not after it is
             applied, which is why we time from AuraRemoved.

       ECD - enemy cooldowns, per player. Started when we SEE the ability used.
             Deliberately NOT inferred from the gap between uses: the logger
             proved gaps are only an upper bound (Ice Block reappeared after
             265s against a 300s cooldown because Cold Snap reset it). Instead
             we start from a known value and correct DOWNWARD when reality
             contradicts us -- a reuse earlier than predicted is hard evidence
             the real cooldown is shorter. That correction is saved and
             reported rather than applied silently.

     Both displays follow target and focus. Your own cooldowns are not here:
     your action bars plus OmniCC already show them.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("cooldowns")

local GetTime       = GetTime
local UnitGUID      = UnitGUID
local UnitExists    = UnitExists
local UnitCanAttack = UnitCanAttack

local DR_SIZE, ECD_SIZE, GAP = 30, 28, 4
local MAX_DR, MAX_ECD = 6, 8

-- [guid][category] = { level = 1..4, resetAt = time or nil while still active }
local dr = {}
-- [guid][spellID] = { readyAt = time, startedAt = time }
local ecd = {}

local drFrame, ecdFrame
local drIcons, ecdIcons = {}, {}

----------------------------------------------------------------------
-- tracking
----------------------------------------------------------------------

local function BumpDR(guid, cat)
	dr[guid] = dr[guid] or {}
	local e = dr[guid][cat]
	local now = GetTime()
	if not e or (e.resetAt and e.resetAt < now) then
		dr[guid][cat] = { level = 1, resetAt = nil }
	else
		e.level = math.min((e.level or 1) + 1, 4)
		e.resetAt = nil          -- still active; the timer starts when it fades
	end
end

local function FadeDR(guid, cat)
	local e = dr[guid] and dr[guid][cat]
	if e then e.resetAt = GetTime() + ns.DR_RESET end
end

local function StartCD(guid, spellID)
	local info = ns.EnemyCD[spellID]
	if not info then return end
	local now = GetTime()
	local cd = (FycoPvPDB.cdLearned and FycoPvPDB.cdLearned[spellID]) or info.cd

	ecd[guid] = ecd[guid] or {}
	local prev = ecd[guid][spellID]

	-- Used again while we still believed it was on cooldown: our number is too
	-- high. Trust what we just saw, but ignore absurdly short repeats (a doubled
	-- combat log entry) by requiring at least 2 seconds.
	if prev and prev.readyAt > now and (now - prev.startedAt) > 2 then
		local observed = now - prev.startedAt
		FycoPvPDB.cdLearned = FycoPvPDB.cdLearned or {}
		FycoPvPDB.cdLearned[spellID] = observed
		ns:Print(string.format("|cffffff00learned|r %s cooldown is %.0fs, not %.0fs",
			info.name, observed, cd))
		cd = observed
	end

	ecd[guid][spellID] = { readyAt = now + cd, startedAt = now }
end

----------------------------------------------------------------------
-- frames
----------------------------------------------------------------------

local function MakeIcon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(size)
	f:SetHeight(size)

	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
	f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)

	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints(f)
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	f.label = f:CreateFontString(nil, "OVERLAY")
	f.label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	f.label:SetPoint("TOP", f, "BOTTOM", 0, -1)

	f.time = f:CreateFontString(nil, "OVERLAY")
	f.time:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
	f.time:SetPoint("CENTER", f, "CENTER", 0, 0)

	f:Hide()
	return f
end

local function MakeRow(name, defPos, key, icons, count, size)
	local f = CreateFrame("Frame", ADDON .. name, UIParent)
	f:SetWidth(count * (size + GAP))
	f:SetHeight(size + 14)
	f:SetMovable(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		FycoPvPDB[key] = { p, x, y }
	end)
	local p = FycoPvPDB[key] or defPos
	f:SetPoint(p[1], UIParent, p[1], p[2], p[3])

	for i = 1, count do
		icons[i] = MakeIcon(f, size)
	end

	-- Laid out once, in a fixed grid. These rows always show a prefix of the
	-- icons and hide the rest, so slot 8 sits at the start of the second row
	-- whether or not it is currently visible -- no re-layout needed, and the
	-- icons never shuffle under you mid-fight.
	local w, h = ns:LayoutIcons(f, icons, count, GAP)
	f:SetWidth(math.max(size, w))
	f:SetHeight(math.max(size, h))
	return f
end

----------------------------------------------------------------------
-- display
----------------------------------------------------------------------

local function WatchedGUID()
	if UnitExists("target") and UnitCanAttack("player", "target") then
		return UnitGUID("target")
	end
	if UnitExists("focus") and UnitCanAttack("player", "focus") then
		return UnitGUID("focus")
	end
end

local function Refresh(now)
	if not ns:Enabled("cooldowns") then
		for i = 1, MAX_DR  do drIcons[i]:Hide() end
		for i = 1, MAX_ECD do ecdIcons[i]:Hide() end
		return
	end
	local guid = WatchedGUID()

	-- DR row
	local n = 0
	if guid and dr[guid] then
		for cat, e in pairs(dr[guid]) do
			if e.resetAt and e.resetAt < now then
				dr[guid][cat] = nil          -- window fully reopened
			elseif n < MAX_DR then
				n = n + 1
				local icon = drIcons[n]
				local sid = ns.DRIcon[cat]
				if sid then icon.tex:SetTexture(select(3, GetSpellInfo(sid))) end
				local c = ns.DRLevelColor[e.level] or { 1, 1, 1 }
				icon.border:SetTexture(c[1], c[2], c[3], 1)
				icon.label:SetText(ns.DRLabel[e.level] or "")
				icon.label:SetTextColor(c[1], c[2], c[3])
				icon.time:SetText(e.resetAt
					and string.format("%d", math.max(0, e.resetAt - now)) or "")
				icon:Show()
			end
		end
	end
	for i = n + 1, MAX_DR do drIcons[i]:Hide() end

	-- enemy cooldown row
	local m = 0
	if guid then
		local u = ns.units[guid]
		local isPlayer = u and u.utype == "player"
		local mine = ecd[guid]
		local list = {}
		for spellID, info in pairs(ns.EnemyCD) do
			local rec = mine and mine[spellID]
			if rec or (info.always and isPlayer) then
				list[#list + 1] = { id = spellID, info = info, rec = rec }
			end
		end
		table.sort(list, function(a, b) return a.info.prio > b.info.prio end)

		for i = 1, #list do
			if m >= MAX_ECD then break end
			local it = list[i]
			m = m + 1
			local icon = ecdIcons[m]
			icon.tex:SetTexture(select(3, GetSpellInfo(it.id)))
			local left = it.rec and (it.rec.readyAt - now) or 0
			if left > 0 then
				icon.border:SetTexture(0.75, 0.15, 0.15, 1)
				icon.tex:SetDesaturated(true)
				icon.time:SetText(left >= 60 and string.format("%dm", math.ceil(left / 60))
				                              or string.format("%d", left))
				icon.time:SetTextColor(1, 1, 1)
				icon.label:SetText("")
			else
				icon.border:SetTexture(0.20, 0.80, 0.30, 1)
				icon.tex:SetDesaturated(false)
				icon.time:SetText("")
				icon.label:SetText("UP")
				icon.label:SetTextColor(0.3, 1, 0.4)
			end
			icon:Show()
		end
	end
	for i = m + 1, MAX_ECD do ecdIcons[i]:Hide() end
end

----------------------------------------------------------------------
-- load
----------------------------------------------------------------------

function M:OnLoad()
	drFrame  = MakeRow("DR",  { "CENTER", -180, -90 }, "drPos",  drIcons,  MAX_DR,  DR_SIZE)
	ecdFrame = MakeRow("ECD", { "CENTER",  180, -90 }, "ecdPos", ecdIcons, MAX_ECD, ECD_SIZE)

	ns:Subscribe("AuraApplied", function(guid, spellID, srcGUID)
		local cc = ns.CC[spellID]
		if cc and guid then
			BumpDR(guid, cc.dr)
			-- Announce and Stats both want to know how diminished that was.
			-- Publishing it here rather than letting them read the table keeps
			-- the answer correct regardless of module load order: BumpDR has
			-- already run, so this level describes THIS application.
			local e = dr[guid] and dr[guid][cc.dr]
			ns:Fire("DRApplied", guid, cc.dr, e and e.level or 1, srcGUID, spellID)
		end
		-- some defensives are only ever seen as an aura, never as a cast
		if srcGUID and ns.EnemyCD[spellID] and srcGUID ~= ns.player then
			StartCD(srcGUID, spellID)
		end
	end)

	ns:Subscribe("AuraRemoved", function(guid, spellID)
		local cc = ns.CC[spellID]
		if cc and guid then FadeDR(guid, cc.dr) end
	end)

	ns:Subscribe("CastSuccess", function(srcGUID, spellID)
		if srcGUID and srcGUID ~= ns.player then StartCD(srcGUID, spellID) end
	end)

	ns:OnTick(function(now)
		Refresh(now)
		if not ns._cdSweep or now - ns._cdSweep > 30 then
			ns._cdSweep = now
			for guid in pairs(ecd) do
				if not ns.units[guid] then ecd[guid] = nil end
			end
			for guid in pairs(dr) do
				if not ns.units[guid] then dr[guid] = nil end
			end
		end
	end)

	-- New opponents: every DR window and every cooldown we were counting
	-- belonged to people who are no longer here.
	ns:Subscribe("MatchStart", function()
		dr, ecd = {}, {}
	end)

	ns:Subscribe("ToggleLock", function()
		if drFrame:IsMouseEnabled() then
			drFrame:EnableMouse(false)
			ecdFrame:EnableMouse(false)
		else
			drFrame:EnableMouse(true)
			ecdFrame:EnableMouse(true)
			for i = 1, 3 do
				local ic = drIcons[i]
				ic.tex:SetTexture(select(3, GetSpellInfo(ns.DRIcon.fear)))
				local c = ns.DRLevelColor[i]
				ic.border:SetTexture(c[1], c[2], c[3], 1)
				ic.label:SetText(ns.DRLabel[i])
				ic.label:SetTextColor(c[1], c[2], c[3])
				ic.time:SetText("12")
				ic:Show()
			end
			for i = 1, 3 do
				local ic = ecdIcons[i]
				ic.tex:SetTexture(select(3, GetSpellInfo(42292)))
				ic.tex:SetDesaturated(i ~= 1)
				if i == 1 then
					ic.border:SetTexture(0.20, 0.80, 0.30, 1)
					ic.label:SetText("UP")
					ic.label:SetTextColor(0.3, 1, 0.4)
					ic.time:SetText("")
				else
					ic.border:SetTexture(0.75, 0.15, 0.15, 1)
					ic.label:SetText("")
					ic.time:SetText("1m")
				end
				ic:Show()
			end
		end
	end)

	--- Report every cooldown the tracker has corrected against the table.
	function ns:CDReport()
		local any = false
		for spellID, secs in pairs(FycoPvPDB.cdLearned or {}) do
			local info = ns.EnemyCD[spellID]
			ns:Print(string.format("  %s (%d): observed %.0fs, table says %s",
				info and info.name or "?", spellID, secs,
				info and tostring(info.cd) or "?"))
			any = true
		end
		if not any then ns:Print("  nothing corrected yet - the table values still hold") end
	end
end
