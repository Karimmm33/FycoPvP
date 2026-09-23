--[[ FycoPvP - Modules/Control.lua
     Step 1. Shows what crowd control is on YOU right now: one large icon with
     a cooldown swipe, a timer, and a border coloured by category.
     Reads UnitDebuff("player") directly, so durations are real API values and
     no combat-log guessing is involved. That is why it is the first module.
     Loaded by Core.lua at PLAYER_LOGIN via the module registry.              ]]

local ADDON, ns = ...
local M = ns:Module("control")

local UnitDebuff = UnitDebuff
local SIZE = 64

local frame, icon, cd, timer, border, label
local active   -- { spellID, cat, expires, duration, icon, name }

----------------------------------------------------------------------
-- frame
----------------------------------------------------------------------

local function Build()
	frame = CreateFrame("Frame", ADDON .. "Control", UIParent)
	frame:SetWidth(SIZE)
	frame:SetHeight(SIZE)
	frame:SetMovable(true)
	frame:EnableMouse(false)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		FycoPvPDB.controlPos = { p, x, y }
	end)

	local pos = FycoPvPDB.controlPos
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
	end

	icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(frame)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	border = frame:CreateTexture(nil, "BACKGROUND")
	border:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
	border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)

	cd = CreateFrame("Cooldown", ADDON .. "ControlCD", frame, "CooldownFrameTemplate")
	cd:SetAllPoints(frame)
	cd:SetReverse(true)
	-- OmniCC hooks SetCooldown on the Cooldown metatable, so it would stack its
	-- own text on top of ours. This is its documented opt-out (config.lua:265).
	cd.noCooldownCount = true

	timer = frame:CreateFontString(nil, "OVERLAY")
	timer:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
	timer:SetPoint("BOTTOM", frame, "BOTTOM", 0, -18)

	label = frame:CreateFontString(nil, "OVERLAY")
	label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	label:SetPoint("TOP", frame, "TOP", 0, 16)

	frame:Hide()
end

----------------------------------------------------------------------
-- detection
----------------------------------------------------------------------

--- Highest-priority CC currently on the player, or nil.
local function Worst()
	local best, bestPrio
	for i = 1, 40 do
		local name, _, tex, _, _, duration, expires, _, _, _, spellID = UnitDebuff("player", i)
		if not name then break end
		local info = spellID and ns.CC[spellID]
		if info then
			local prio = ns.CCPriority[info.cat] or 0
			if not bestPrio or prio > bestPrio then
				bestPrio = prio
				best = {
					spellID  = spellID,
					cat      = info.cat,
					expires  = expires,
					duration = duration,
					icon     = tex,
					name     = name,
				}
			end
		end
	end
	return best
end

local function Show(cc)
	active = cc
	icon:SetTexture(cc.icon)
	local c = ns.CCColor[cc.cat] or { 1, 1, 1 }
	border:SetTexture(c[1], c[2], c[3], 1)
	label:SetText(string.upper(cc.cat))
	label:SetTextColor(c[1], c[2], c[3])
	if cc.duration and cc.duration > 0 and cc.expires then
		cd:SetCooldown(cc.expires - cc.duration, cc.duration)
	end
	frame:Show()
	-- the spell's own voice line where we have one, else the category cue
	ns:SpellSound(cc.spellID, ns.CCSound[cc.cat] or "ccbreak", 1.0)
end

local function Hide()
	if active then
		active = nil
		timer:SetText("")
		frame:Hide()
	end
end

local function Refresh()
	if not ns:Enabled("control") then Hide() return end
	local cc = Worst()
	if not cc then
		Hide()
		return
	end
	-- only restart the swipe when this is genuinely a new application
	if not active or active.spellID ~= cc.spellID
	   or (cc.expires and active.expires and cc.expires > active.expires + 0.1) then
		Show(cc)
	else
		active.expires = cc.expires
	end
end

----------------------------------------------------------------------
-- load
----------------------------------------------------------------------

function M:OnLoad()
	Build()

	ns:Subscribe("UnitAura", function(unit)
		if unit == "player" then Refresh() end
	end)

	ns:Subscribe("ToggleLock", function()
		local unlocked = frame:IsMouseEnabled()
		if unlocked then
			frame:EnableMouse(false)
			if not active then frame:Hide() end
			ns:Print("control frame locked")
		else
			frame:EnableMouse(true)
			frame:Show()
			icon:SetTexture("Interface\\Icons\\Spell_Shadow_Possession")
			border:SetTexture(1, 1, 1, 1)
			label:SetText("DRAG ME")
			label:SetTextColor(1, 1, 1)
			timer:SetText("")
			ns:Print("control frame unlocked - drag it, then |cffffff00/fyco lock|r again")
		end
	end)

	ns:OnTick(function(now)
		if not active or not active.expires or active.expires == 0 then return end
		local left = active.expires - now
		if left <= 0 then
			Refresh()
			return
		end
		timer:SetText(left < 10 and string.format("%.1f", left) or string.format("%d", left))
		timer:SetTextColor(1, left < 1.5 and 0.2 or 1, 0.2)
	end)

	Refresh()
end
