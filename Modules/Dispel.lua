--[[ FycoPvP - Modules/Dispel.lua
     The target and focus buff bar, in two jobs that used to be tangled into
     one and are now kept apart:

       1. SHOW every buff, on anyone -- friendly, neutral or hostile -- with an
          icon, a cooldown sweep, a timer and a stack count. This replaces
          Blizzard's target buff row rather than sitting beside it.

       2. HIGHLIGHT the ones you could actually strip: drawn larger, pulsing,
          and outlined in the dispel type's colour. That only ever applies to a
          hostile unit, because there is nothing to steal off a friend.

     An earlier version hid the WHOLE ROW unless the unit was attackable, which
     made it look broken on every friendly target. Showing and highlighting are
     now separate decisions: `hostile` gates the glow, never the row.

     WHICH BUFFS GLOW. Two filters, and the second is deliberately permissive:
       * the buff's dispel type must be one you ticked (Magic, for a warlock)
       * AND, if the watch list has anything in it, the name must be on it.
         An EMPTY watch list means every dispellable buff glows, which is the
         default -- you should have to opt in to seeing less, not more.

     WHICH BUFFS COUNT AS DISPELLABLE. 3.3.5a is awkward. UnitBuff returns:
       name, rank, icon, count, dispelType, duration, expires, caster,
       isStealable, shouldConsolidate, spellId
     For a buff on a hostile unit `dispelType` is frequently nil even when the
     buff is plainly magic, while `isStealable` -- the flag Spellsteal uses --
     is set. So a buff is treated as Magic if EITHER says so. That is a
     heuristic, which is why /fyco dispel debug prints what the API actually
     returned: if this core disagrees, that command shows it.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("dispel")

local UnitBuff      = UnitBuff
local UnitExists    = UnitExists
local UnitName      = UnitName
local UnitCanAttack = UnitCanAttack

local MAX_ICONS = 16
local GAP       = 3

-- how fast the highlight breathes, and between which alphas
local PULSE_MIN, PULSE_MAX, PULSE_PERIOD = 0.35, 1.00, 1.1

local rows = {}     -- [unit] = frame

----------------------------------------------------------------------
-- config
----------------------------------------------------------------------

local function cfg()
	FycoPvPDB.dispel = FycoPvPDB.dispel or {}
	return FycoPvPDB.dispel
end

local function Defaults()
	local c = cfg()

	if c.types == nil then
		-- start from what this class can actually strip off an enemy
		local _, class = UnitClass("player")
		local able = ns.ClassOffensiveDispel[class or ""] or {}
		c.types = {}
		for i = 1, #ns.DispelTypes do
			local t = ns.DispelTypes[i]
			c.types[t] = able[t] and true or false
		end
	end

	-- Empty on purpose: with no watch list, everything dispellable glows.
	c.watch = c.watch or {}

	if c.showAll      == nil then c.showAll      = true  end
	if c.hideBlizzard == nil then c.hideBlizzard = false end
	if c.target       == nil then c.target       = true  end
	if c.focus        == nil then c.focus        = true  end
	if c.size         == nil then c.size         = 26    end
	if c.bigSize      == nil then c.bigSize      = 34    end
	c.pos = c.pos or {}

	-- settings from the version that showed only dispellable buffs
	c.showUntracked, c.onlyDispellable = nil, nil
	return c
end

----------------------------------------------------------------------
-- construction
----------------------------------------------------------------------

local function MakeIcon(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(26)
	f:SetHeight(26)

	-- The coloured border is a texture *behind* the icon, showing as an
	-- outline because it is inset by two pixels on every side. No border art
	-- has to ship with the addon this way.
	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetPoint("TOPLEFT", -2, 2)
	f.border:SetPoint("BOTTOMRIGHT", 2, -2)

	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints(f)
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- CooldownFrameTemplate is NOT optional. A bare Cooldown frame is not
	-- initialised, and SetCooldown on one throws -- which killed this entire
	-- row silently, because the error fired before the row was ever shown.
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints(f)
	f.cd.noCooldownCount = true    -- opt out of cooldown text; we draw our own

	f.time = f:CreateFontString(nil, "OVERLAY")
	f.time:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	f.time:SetPoint("BOTTOM", f, "BOTTOM", 0, -1)

	f.count = f:CreateFontString(nil, "OVERLAY")
	f.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	f.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)

	-- Blizzard's own aura tooltip on hover. Update() keeps tipUnit/tipIndex
	-- pointing at the right aura.
	ns:AuraTooltip(f)

	f:Hide()
	return f
end

local function MakeRow(unit, label, def)
	local f = CreateFrame("Frame", ADDON .. "Dispel" .. unit, UIParent)
	f:SetWidth(MAX_ICONS * 30)
	f:SetHeight(40)
	f:SetMovable(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		cfg().pos[unit] = { p, x, y }
	end)

	local p = cfg().pos[unit] or def
	f:SetPoint(p[1], UIParent, p[1], p[2], p[3])

	f.label = f:CreateFontString(nil, "OVERLAY")
	f.label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
	f.label:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
	f.label:SetText(label)
	f.label:Hide()

	f.icons = {}
	for i = 1, MAX_ICONS do
		f.icons[i] = MakeIcon(f)
	end
	f.unit = unit
	f:Hide()
	return f
end

----------------------------------------------------------------------
-- Blizzard's own buff row
----------------------------------------------------------------------

--- Hide the stock target/focus BUFF buttons. Debuffs are left alone: other
--- parts of this addon do not replace those, and silently removing them would
--- cost information rather than duplication.
local function HideBlizzardBuffs()
	for i = 1, 32 do
		local b = _G["TargetFrameBuff" .. i]
		if b then b:Hide() end
		local f = _G["FocusFrameBuff" .. i]
		if f then f:Hide() end
	end
end

----------------------------------------------------------------------
-- scanning
----------------------------------------------------------------------

--- What kind of buff is this, and is it a type you asked to track?
local function Classify(dispelType, isStealable, c)
	-- isStealable is Spellsteal's own flag. On this client it is set for magic
	-- buffs on hostile units far more reliably than dispelType is populated,
	-- so it stands in for "Magic" when dispelType came back empty.
	local kind = dispelType
	if (not kind or kind == "") and isStealable then kind = "Magic" end
	if not kind or kind == "" then return nil, false end
	return kind, (c.types[kind] == true)
end

--- Does this one get the big pulsing treatment?
local function ShouldGlow(name, tracked, hostile, c)
	if not hostile then return false end   -- nothing to strip off a friend
	if not tracked then return false end   -- not a type you can remove
	if next(c.watch) == nil then return true end   -- empty list: all of them
	return c.watch[name:lower()] == true
end

local buf = {}

local function Collect(unit, c, hostile)
	for i = 1, MAX_ICONS do buf[i] = nil end
	local n = 0

	for i = 1, 40 do
		local name, _, icon, count, dispelType, duration, expires,
		      _, isStealable = UnitBuff(unit, i)
		if not name then break end

		local kind, tracked = Classify(dispelType, isStealable, c)
		local glow = ShouldGlow(name, tracked, hostile, c)

		-- showAll makes this a full replacement for Blizzard's bar. Turn it
		-- off and only the buffs you could dispel are listed.
		if (c.showAll or glow) and n < MAX_ICONS then
			n = n + 1
			buf[n] = {
				name = name, icon = icon, count = count or 0,
				kind = kind, glow = glow,
				-- the REAL UnitBuff index, kept because the list is about to
				-- be sorted and the tooltip has to ask the game for this exact
				-- aura, not for whatever ends up in this display slot
				idx = i,
				prio = ns.DispelPriority[name] or 0,
				duration = duration or 0, expires = expires or 0,
			}
		end
	end

	-- Glowing first, then by priority, then soonest to expire. UnitBuff's own
	-- order puts nothing useful first, so a fixed sort is the only way the
	-- icon that matters reliably lands in slot one.
	for a = 2, n do
		local item, b = buf[a], a - 1
		while b >= 1 do
			local o = buf[b]
			local swap = false
			if item.glow and not o.glow then
				swap = true
			elseif item.glow == o.glow then
				if o.prio < item.prio then
					swap = true
				elseif o.prio == item.prio
				       and (item.expires or 0) > 0
				       and (o.expires or 0) > (item.expires or 0) then
					swap = true
				end
			end
			if not swap then break end
			buf[b + 1] = o
			b = b - 1
		end
		buf[b + 1] = item
	end

	return n
end

----------------------------------------------------------------------
-- drawing
----------------------------------------------------------------------

local function Update(now)
	local c = cfg()

	if not ns:Enabled("dispel") then
		for _, row in pairs(rows) do
			if row:IsShown() and not row.preview then row:Hide() end
		end
		return
	end

	if c.hideBlizzard then HideBlizzardBuffs() end

	local pulse = PULSE_MIN + (PULSE_MAX - PULSE_MIN)
		* (0.5 + 0.5 * math.sin(now * (2 * math.pi / PULSE_PERIOD)))

	for unit, row in pairs(rows) do
		if row.preview then
			-- leave the placeholder alone while frames are unlocked
		elseif not c[unit] or not UnitExists(unit) then
			if row:IsShown() then row:Hide() end
		else
			-- hostility decides the GLOW, never whether the row is shown
			local hostile = UnitCanAttack("player", unit) and true or false
			local n = Collect(unit, c, hostile)

			if n == 0 then
				if row:IsShown() then row:Hide() end
			else
				for i = 1, MAX_ICONS do
					local f, a = row.icons[i], buf[i]
					if i <= n and a then
						local size = a.glow and c.bigSize or c.size
						f:SetWidth(size)
						f:SetHeight(size)

						f.tex:SetTexture(a.icon)

						if a.glow then
							local col = ns.DebuffColor[a.kind or "none"]
							            or ns.DebuffColor.none
							f.border:SetTexture(col[1], col[2], col[3], 1)
							f.border:SetAlpha(pulse)
							f.border:Show()
						elseif a.kind then
							-- dispellable but not one of yours: colour it,
							-- quietly, so the type is still readable
							local col = ns.DebuffColor[a.kind] or ns.DebuffColor.none
							f.border:SetTexture(col[1], col[2], col[3], 1)
							f.border:SetAlpha(0.45)
							f.border:Show()
						else
							f.border:SetTexture(0, 0, 0, 1)
							f.border:SetAlpha(0.7)
							f.border:Show()
						end

						if a.duration > 0 and a.expires > 0 then
							f.cd:SetCooldown(a.expires - a.duration, a.duration)
							local left = a.expires - now
							f.time:SetText(left >= 60
								and string.format("%dm", math.floor(left / 60 + 0.5))
								or string.format("%d", math.max(0, left)))
						else
							f.cd:SetCooldown(0, 0)
							f.time:SetText("")
						end

						f.count:SetText(a.count > 1 and a.count or "")
						f:SetAlpha(1)

						-- point the tooltip at this aura, and keep the
						-- remaining-time line counting down while hovered
						f.tipUnit, f.tipIndex, f.tipHarmful = unit, a.idx, false
						ns:AuraTooltipRefresh(f)

						f:Show()
					else
						f.tipUnit, f.tipIndex = nil, nil
						f:Hide()
					end
				end

				-- positioned after sizing, so a highlighted icon's larger
				-- footprint is what the wrap actually measures
				local w, h = ns:LayoutIcons(row, row.icons, n, GAP)
				row:SetWidth(math.max(c.size, w))
				row:SetHeight(math.max(c.size, h))

				if not row:IsShown() then row:Show() end
			end
		end
	end
end

----------------------------------------------------------------------
-- the watch list
----------------------------------------------------------------------

local function WatchCommand(rest)
	local c = cfg()
	rest = rest or ""

	if rest == "" then
		local names = {}
		for k in pairs(c.watch) do names[#names + 1] = k end
		table.sort(names)
		if #names == 0 then
			ns:Print("watch list is |cffffff00empty|r, so |cff00ff00every|r "
			      .. "dispellable buff glows. That is the default.")
		else
			ns:Print(#names .. " buffs glow (everything else stays plain):")
			for i = 1, #names do ns:Print("  " .. names[i]) end
		end
		ns:Print("  |cffffff00/fyco dispel watch <buff name>|r adds or removes one")
		ns:Print("  |cffffff00/fyco dispel watch defaults|r loads the built-in list")
		ns:Print("  |cffffff00/fyco dispel watch clear|r empties it again")
		return
	end

	if rest:lower() == "clear" then
		c.watch = {}
		ns:Print("watch list cleared - every dispellable buff glows again")
		return
	end

	if rest:lower() == "defaults" then
		c.watch = {}
		local n = 0
		for name, prio in pairs(ns.DispelPriority) do
			if prio >= 2 then
				c.watch[name:lower()] = true
				n = n + 1
			end
		end
		ns:Print("loaded " .. n .. " buffs into the watch list - only those glow now")
		return
	end

	local key = rest:lower()
	if c.watch[key] then
		c.watch[key] = nil
		ns:Print("|cffff4040removed|r " .. rest)
	else
		c.watch[key] = true
		ns:Print("|cff00ff00watching|r " .. rest)
	end
end

----------------------------------------------------------------------
-- commands
----------------------------------------------------------------------

--- /fyco dispel debug -- what the API actually returned for your target.
function ns:DispelDebug()
	local unit = UnitExists("target") and "target" or "focus"
	if not UnitExists(unit) then
		ns:Print("no target or focus to inspect")
		return
	end

	local c = cfg()
	local hostile = UnitCanAttack("player", unit) and true or false
	ns:Print("buffs on " .. (UnitName(unit) or unit)
		.. (hostile and " |cffff8080(hostile)|r" or " |cff80ff80(friendly - nothing can be dispelled)|r"))
	ns:Print("|cff808080  name / dispelType / stealable / result|r")

	local any = false
	for i = 1, 40 do
		local name, _, _, _, dispelType, _, _, _, isStealable = UnitBuff(unit, i)
		if not name then break end
		any = true
		local kind, tracked = Classify(dispelType, isStealable, c)
		local verdict
		if ShouldGlow(name, tracked, hostile, c) then
			verdict = "|cff00ff00GLOWS|r"
		elseif kind then
			verdict = "|cff808080" .. kind .. ", shown plain|r"
		else
			verdict = "|cff606060not dispellable|r"
		end
		ns:Print(string.format("  %-26s %-8s %-5s %s",
			name:sub(1, 26), tostring(dispelType or "-"),
			isStealable and "yes" or "no", verdict))
	end
	if not any then ns:Print("  (none)") end
end

--- /fyco dispel [type|watch|showall|blizzard|target|focus|debug]
function ns:DispelConfig(rest)
	local c = cfg()
	rest = rest or ""

	local sub, args = rest:match("^(%S*)%s*(.-)%s*$")
	sub = (sub or ""):lower()

	if sub == "debug" then return ns:DispelDebug() end
	if sub == "watch" then return WatchCommand(args) end

	if sub == "" then
		local on = {}
		for i = 1, #ns.DispelTypes do
			local t = ns.DispelTypes[i]
			if c.types[t] then on[#on + 1] = t end
		end
		local watched = 0
		for _ in pairs(c.watch) do watched = watched + 1 end

		ns:Print("buff bar: |cffffff00" .. (c.showAll and "all buffs" or "dispellable only")
			.. "|r   target " .. (c.target and "on" or "off")
			.. " | focus " .. (c.focus and "on" or "off"))
		ns:Print("glows for: |cffffff00" ..
			(#on > 0 and table.concat(on, ", ") or "nothing") .. "|r on hostile units"
			.. (watched > 0 and (", limited to " .. watched .. " watched buffs")
			                or ", any dispellable buff"))
		ns:Print("  |cffffff00/fyco dispel magic|curse|poison|disease|r toggles a type")
		ns:Print("  |cffffff00/fyco dispel watch|r manages which buffs glow")
		ns:Print("  |cffffff00/fyco dispel showall|r shows every buff, or only dispellable ones")
		ns:Print("  |cffffff00/fyco dispel blizzard|r hides Blizzard's own buff row")
		ns:Print("  |cffffff00/fyco dispel debug|r explains your current target")
		ns:Print("|cff808080Only Magic can be taken off an enemy in 3.3.5a. The other three")
		ns:Print("are offered for completeness, not because they will fire.|r")
		return
	end

	for i = 1, #ns.DispelTypes do
		local t = ns.DispelTypes[i]
		if sub == t:lower() then
			c.types[t] = not c.types[t]
			ns:Print(t .. " " ..
				(c.types[t] and "|cff00ff00glows|r" or "|cffff0000ignored|r"))
			return
		end
	end

	if sub == "showall" then
		c.showAll = not c.showAll
		ns:Print(c.showAll and "showing |cff00ff00every|r buff"
		                   or "showing |cffffff00only dispellable|r buffs")
		return
	end

	if sub == "blizzard" then
		c.hideBlizzard = not c.hideBlizzard
		ns:Print("Blizzard's buff row " ..
			(c.hideBlizzard and "|cffff0000hidden|r" or "|cff00ff00shown|r")
			.. (c.hideBlizzard and "" or " - |cffffff00/reload|r to bring it back"))
		return
	end

	if sub == "target" or sub == "focus" then
		c[sub] = not c[sub]
		ns:Print(sub .. " " .. (c[sub] and "on" or "off"))
		return
	end

	ns:Print("not a setting: " .. sub .. " - try |cffffff00/fyco dispel|r")
end

----------------------------------------------------------------------

function M:OnLoad()
	Defaults()

	rows.target = MakeRow("target", "Target buffs", { "CENTER", 0, 120 })
	rows.focus  = MakeRow("focus",  "Focus buffs",  { "CENTER", 0, 86 })

	ns:OnTick(Update)

	-- Blizzard re-shows its buff buttons whenever it refreshes them, so the
	-- hiding has to run after that rather than only once.
	if TargetFrame_UpdateAuras then
		hooksecurefunc("TargetFrame_UpdateAuras", function()
			if cfg().hideBlizzard and ns:Enabled("dispel") then
				HideBlizzardBuffs()
			end
		end)
	end

	ns:Subscribe("ToggleLock", function()
		local c = cfg()
		for _, row in pairs(rows) do
			if row:IsMouseEnabled() then
				row:EnableMouse(false)
				row.preview = nil
				row.label:Hide()
				-- hand the mouse back to the icons, so tooltips work again
				for i = 1, MAX_ICONS do row.icons[i]:EnableMouse(true) end
				row:Hide()
			else
				row:EnableMouse(true)
				row.preview = true
				row.label:Show()
				-- An icon that accepts the mouse swallows the drag, and the
				-- row cannot be moved. Tooltips can wait until it is locked.
				for i = 1, MAX_ICONS do row.icons[i]:EnableMouse(false) end
				for i = 1, MAX_ICONS do
					local f = row.icons[i]
					if i <= 4 then
						local size = (i == 1) and c.bigSize or c.size
						f:SetWidth(size)
						f:SetHeight(size)
						f.tex:SetTexture("Interface\\Icons\\Spell_Holy_PowerWordShield")
						local col = (i == 1) and ns.DebuffColor.Magic or { 0, 0, 0 }
						f.border:SetTexture(col[1], col[2], col[3], 1)
						f.border:SetAlpha(i == 1 and 1 or 0.7)
						f.border:Show()
						f.cd:SetCooldown(0, 0)
						f.time:SetText("12")
						f.count:SetText("")
						f:SetAlpha(1)
						f:Show()
					else
						f:Hide()
					end
				end
				local w, h = ns:LayoutIcons(row, row.icons, 4, GAP)
				row:SetWidth(math.max(c.size, w))
				row:SetHeight(math.max(c.size, h))
				row:Show()
			end
		end
	end)
end
