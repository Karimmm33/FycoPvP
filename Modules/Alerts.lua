--[[ FycoPvP - Modules/Alerts.lua
     Step 5. The "stop casting NOW" layer. Two separate displays, because the
     things worth shouting about come in two shapes:

       1. STATE  - an enemy defensive that is up for a few seconds
                   (Spell Reflection, Ice Block, Divine Shield, AMS...).
                   Big centred icon with a countdown, highest priority wins.
                   Driven by UnitBuff on target and focus.

       2. EVENT  - something that happened once and has no lasting aura
                   (PvP trinket, Every Man for Himself). A text banner that
                   fades. Driven by the combat log through Core's CastSuccess
                   message, because a trinket leaves no buff behind -- an aura
                   scan would never see it at all.

     Both speak through ns:SpellSound, so each spell uses its own voice line
     and falls back to a category cue.
     Loaded by Core.lua at PLAYER_LOGIN. Replaces TellMeWhen.                 ]]

local ADDON, ns = ...
local M = ns:Module("alerts")

local UnitBuff      = UnitBuff
local UnitExists    = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitGUID      = UnitGUID
local GetTime       = GetTime

local ICON = 88
local WATCH = { "target", "focus" }

-- Events worth a banner even though they leave nothing to scan for.
local EVENT_CASTS = {
	[42292] = { text = "TRINKET", sound = "trinket" },
	[59752] = { text = "TRINKET", sound = "trinket" },  -- Every Man for Himself
	[7744]  = { text = "WOTF",    sound = "fear"    },  -- Will of the Forsaken
}

local alert, banner
local current          -- { spellID, expires, unit, guid, ... }
local announced = {}   -- [guid..":"..spellID] = expiry, so we speak once

----------------------------------------------------------------------
-- frames
----------------------------------------------------------------------

local function BuildAlert()
	local f = CreateFrame("Frame", ADDON .. "Alert", UIParent)
	f:SetWidth(ICON)
	f:SetHeight(ICON)
	f:SetMovable(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		FycoPvPDB.alertPos = { p, x, y }
	end)

	local p = FycoPvPDB.alertPos or { "CENTER", 0, 120 }
	f:SetPoint(p[1], UIParent, p[1], p[2], p[3])

	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 4)
	f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
	f.border:SetTexture(1, 0.1, 0.1, 1)

	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints(f)
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	f.unit = f:CreateFontString(nil, "OVERLAY")
	f.unit:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
	f.unit:SetPoint("BOTTOM", f, "TOP", 0, 6)

	f.name = f:CreateFontString(nil, "OVERLAY")
	f.name:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
	f.name:SetPoint("TOP", f, "BOTTOM", 0, -6)

	f.time = f:CreateFontString(nil, "OVERLAY")
	f.time:SetFont("Fonts\\FRIZQT__.TTF", 30, "OUTLINE")
	f.time:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.time:SetTextColor(1, 1, 1)

	f:Hide()
	return f
end

local function BuildBanner()
	local f = CreateFrame("Frame", ADDON .. "Banner", UIParent)
	f:SetWidth(400)
	f:SetHeight(40)
	f:SetMovable(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		FycoPvPDB.bannerPos = { p, x, y }
	end)

	local p = FycoPvPDB.bannerPos or { "CENTER", 0, 40 }
	f:SetPoint(p[1], UIParent, p[1], p[2], p[3])

	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetFont("Fonts\\FRIZQT__.TTF", 28, "OUTLINE")
	f.text:SetPoint("CENTER", f, "CENTER", 0, 0)

	f:Hide()
	return f
end

----------------------------------------------------------------------
-- banner
----------------------------------------------------------------------

local bannerLeft = 0

local function ShowBanner(text, r, g, b)
	banner.text:SetText(text)
	banner.text:SetTextColor(r or 1, g or 0.2, b or 0.2)
	bannerLeft = 2.5
	banner:SetAlpha(1)
	banner:Show()
end

----------------------------------------------------------------------
-- state alerts
----------------------------------------------------------------------

--- Highest-priority enemy defensive across target and focus.
local function Worst()
	local best, bestPrio
	for w = 1, #WATCH do
		local unit = WATCH[w]
		if UnitExists(unit) and UnitCanAttack("player", unit) then
			for i = 1, 40 do
				local name, _, tex, _, _, duration, expires, _, _, _, spellID = UnitBuff(unit, i)
				if not name then break end
				local def = spellID and ns.Defensives[spellID]
				if def and (not bestPrio or def.prio > bestPrio) then
					bestPrio = def.prio
					best = {
						spellID  = spellID,
						name     = def.name or name,
						icon     = tex,
						expires  = expires,
						duration = duration,
						unit     = unit,
						guid     = UnitGUID(unit),
					}
				end
			end
		end
	end
	return best
end

local function Refresh()
	if not ns:Enabled("alerts") then
		if current then current = nil ; alert:Hide() end
		return
	end
	local a = Worst()
	if not a then
		if current then
			current = nil
			alert.time:SetText("")
			alert:Hide()
		end
		return
	end

	if not current or current.spellID ~= a.spellID or current.unit ~= a.unit then
		current = a
		alert.tex:SetTexture(a.icon)
		alert.name:SetText(a.name)
		alert.unit:SetText(a.unit == "focus" and "|cffffcc00FOCUS|r" or "|cffff4444TARGET|r")
		alert:Show()

		-- speak once per aura application, not once per rescan
		local key = tostring(a.guid) .. ":" .. a.spellID
		local now = GetTime()
		if not announced[key] or announced[key] < now then
			announced[key] = (a.expires and a.expires > now) and a.expires or (now + 3)
			ns:SpellSound(a.spellID, "immune", 0.8)
		end
	else
		current.expires = a.expires
	end
end

----------------------------------------------------------------------
-- load
----------------------------------------------------------------------

function M:OnLoad()
	alert  = BuildAlert()
	banner = BuildBanner()

	ns:Subscribe("UnitAura", function(unit)
		if unit == "target" or unit == "focus" then Refresh() end
	end)
	ns:On("PLAYER_TARGET_CHANGED", Refresh)
	ns:On("PLAYER_FOCUS_CHANGED",  Refresh)

	-- trinkets and racials leave no aura to scan, so they come off the combat log
	ns:Subscribe("CastSuccess", function(srcGUID, spellID)
		local ev = EVENT_CASTS[spellID]
		if not ev or srcGUID == ns.player then return end
		local u = ns.units[srcGUID]
		if u and u.utype and u.utype ~= "player" then return end
		local who = (u and u.name) or "Enemy"
		ShowBanner(who .. " - " .. ev.text)
		ns:SpellSound(spellID, ev.sound, 0.8)
		ns:Debug("event cast", who, spellID)
	end)

	ns:OnTick(function(now)
		-- banner fade
		if bannerLeft > 0 then
			bannerLeft = bannerLeft - 0.1
			if bannerLeft <= 0 then
				banner:Hide()
			elseif bannerLeft < 1 then
				banner:SetAlpha(bannerLeft)
			end
		end

		-- alert countdown
		if current then
			if current.expires and current.expires > 0 then
				local left = current.expires - now
				if left <= 0 then
					Refresh()
				else
					alert.time:SetText(left < 10 and string.format("%.1f", left)
					                              or string.format("%d", left))
				end
			else
				alert.time:SetText("")
			end
		end

		-- forget stale announcements so the same spell can speak again later
		for k, expiry in pairs(announced) do
			if expiry < now - 1 then announced[k] = nil end
		end
	end)

	ns:Subscribe("ToggleLock", function()
		if alert:IsMouseEnabled() then
			alert:EnableMouse(false)
			banner:EnableMouse(false)
			if not current then alert:Hide() end
			if bannerLeft <= 0 then banner:Hide() end
		else
			alert:EnableMouse(true)
			banner:EnableMouse(true)
			alert.tex:SetTexture("Interface\\Icons\\Ability_Warrior_ShieldReflection")
			alert.name:SetText("Spell Reflection")
			alert.unit:SetText("|cffff4444TARGET|r")
			alert.time:SetText("4.2")
			alert:Show()
			banner.text:SetText("Enemy - TRINKET")
			banner.text:SetTextColor(1, 0.2, 0.2)
			banner:SetAlpha(1)
			banner:Show()
		end
	end)

	Refresh()
end
