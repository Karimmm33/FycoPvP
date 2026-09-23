--[[ FycoPvP - Modules/Lockout.lua
     Interrupt lockouts, both directions.

       yours   - you got kicked. Which school is sealed, and for how long.
                 Casting into a lockout wastes the global and announces that
                 you were not paying attention.
       theirs  - somebody kicked an enemy. Their healer cannot heal for four
                 seconds, which is the window a kill happens in.

     NOT the same thing as the enemy cooldowns in Cooldowns.lua. That module
     answers "when is their Counterspell back". This one answers "what can be
     cast right now, by me or by them". Adjacent, deliberately kept apart.

     The lockout length comes from ns.Interrupts, looked up BY NAME rather than
     by ID: Kick, Pummel, Counterspell and Shield Bash all have several ranks
     and the table carries one ID each, so an ID lookup would miss every rank
     but one.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("lockout")

local GetTime      = GetTime
local GetSpellInfo = GetSpellInfo
local UnitGUID     = UnitGUID
local UnitName     = UnitName
local UnitExists   = UnitExists
local band         = bit.band

local W, H = 220, 24

-- lock duration by interrupt NAME, built from ns.Interrupts at load
local lockByName = {}

-- [guid] = { until_, dur, school }  for everyone except you
local theirs = {}
-- your own lockout, or nil
local mine

local frame, enemyFS

----------------------------------------------------------------------

local function SchoolInfo(mask)
	local s = mask and ns.School[mask]
	if s then return s[1], s[2], s[3], s[4] end
	-- Combined schools (Frostfire, Shadowfrost) arrive as a mask with several
	-- bits set. Name the first one we find rather than invent a label.
	if mask then
		for flag, info in pairs(ns.School) do
			if band(mask, flag) ~= 0 then
				return info[1], info[2], info[3], info[4]
			end
		end
	end
	return "spell", 0.85, 0.85, 0.85
end

local function Build()
	local f = CreateFrame("Frame", ADDON .. "Lockout", UIParent)
	f:SetWidth(W)
	f:SetHeight(H)
	f:SetMovable(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		FycoPvPDB.lockoutPos = { p, x, y }
	end)

	local p = FycoPvPDB.lockoutPos or { "CENTER", 0, -160 }
	f:SetPoint(p[1], UIParent, p[1], p[2], p[3])

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints(f)
	f.bg:SetTexture(0, 0, 0, 0.6)

	f.bar = CreateFrame("StatusBar", nil, f)
	f.bar:SetAllPoints(f)
	f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	f.bar:SetMinMaxValues(0, 1)

	f.text = f.bar:CreateFontString(nil, "OVERLAY")
	f.text:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
	f.text:SetPoint("LEFT", f, "LEFT", 6, 0)

	f.time = f.bar:CreateFontString(nil, "OVERLAY")
	f.time:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
	f.time:SetPoint("RIGHT", f, "RIGHT", -6, 0)

	-- the enemy line rides under your own bar, so one glance covers both
	enemyFS = f:CreateFontString(nil, "OVERLAY")
	enemyFS:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
	enemyFS:SetPoint("TOP", f, "BOTTOM", 0, -2)
	enemyFS:Hide()

	f:Hide()
	return f
end

----------------------------------------------------------------------
-- tracking
----------------------------------------------------------------------

local function OnInterrupt(srcGUID, dstGUID, kickID, extraID, extraSchool)
	local kickName = kickID and GetSpellInfo(kickID)
	local dur = (kickName and lockByName[kickName]) or 4
	local now = GetTime()

	if dstGUID == ns.player then
		mine = {
			until_  = now + dur,
			dur     = dur,
			school  = extraSchool,
			spell   = extraID and GetSpellInfo(extraID) or nil,
		}
		if FycoPvPDB.lockoutSound then ns:Sound("interrupt", 1) end
	elseif dstGUID then
		theirs[dstGUID] = { until_ = now + dur, dur = dur, school = extraSchool }
	end

	ns:Fire("Lockout", srcGUID, dstGUID, dur, extraSchool, extraID)
end

--- Seconds this GUID stays locked out, or nil. Used by Announce and Stats.
function ns:LockoutLeft(guid)
	if not guid then return nil end
	local e = (guid == ns.player) and mine or theirs[guid]
	if not e then return nil end
	local left = e.until_ - GetTime()
	return left > 0 and left or nil
end

----------------------------------------------------------------------
-- display
----------------------------------------------------------------------

local function Update(now)
	if not frame or frame.preview then return end

	if not ns:Enabled("lockout") then
		if frame:IsShown() then frame:Hide() end
		if enemyFS:IsShown() then enemyFS:Hide() end
		return
	end

	if mine and now < mine.until_ then
		local left = mine.until_ - now
		local name, r, g, b = SchoolInfo(mine.school)
		frame.bar:SetValue(left / mine.dur)
		frame.bar:SetStatusBarColor(r, g, b)
		frame.text:SetText(string.format("|cffff4040LOCKED|r %s", name))
		frame.time:SetText(string.format("%.1f", left))
		if not frame:IsShown() then frame:Show() end
	else
		if mine then mine = nil end
		if frame:IsShown() then frame:Hide() end
	end

	local guid = UnitExists("target") and UnitGUID("target") or nil
	local e = guid and theirs[guid]
	if e and now < e.until_ then
		local name = SchoolInfo(e.school)
		enemyFS:SetText(string.format("|cff40ff40%s LOCKED|r %s |cff40ff40%.1fs|r",
			(UnitName("target") or "target"):upper(), name, e.until_ - now))
		if not enemyFS:IsShown() then enemyFS:Show() end
	elseif enemyFS:IsShown() then
		enemyFS:Hide()
	end

	-- sweep, so a long battleground does not accumulate dead entries
	if not ns._lockSweep or now - ns._lockSweep > 5 then
		ns._lockSweep = now
		for g, t in pairs(theirs) do
			if t.until_ < now then theirs[g] = nil end
		end
	end
end

----------------------------------------------------------------------

function M:OnLoad()
	if FycoPvPDB.lockoutSound == nil then FycoPvPDB.lockoutSound = true end

	for _, info in pairs(ns.Interrupts) do
		if info.name and info.lock then lockByName[info.name] = info.lock end
	end

	frame = Build()
	ns:Subscribe("Interrupt", OnInterrupt)
	ns:OnTick(Update)

	ns:Subscribe("MatchStart", function()
		theirs, mine = {}, nil
	end)

	ns:Subscribe("ToggleLock", function()
		if frame:IsMouseEnabled() then
			frame:EnableMouse(false)
			frame.preview = nil
			frame:Hide()
			enemyFS:Hide()
		else
			frame:EnableMouse(true)
			frame.preview = true
			frame.bar:SetValue(0.7)
			frame.bar:SetStatusBarColor(0.65, 0.35, 0.95)
			frame.text:SetText("|cffff4040LOCKED|r Shadow")
			frame.time:SetText("3.4")
			enemyFS:SetText("|cff40ff40ENEMY LOCKED|r Nature |cff40ff403.1s|r")
			frame:Show()
			enemyFS:Show()
		end
	end)
end
