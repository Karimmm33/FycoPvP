--[[ FycoPvP - Modules/Bar.lua
     A private action bar: only the cooldowns you choose, anywhere you want.

     Three kinds of entry, because they need three different APIs:
       spell - GetSpellCooldown(name). Looked up BY NAME, not by ID, so it
               follows you across ranks as you level instead of silently
               tracking a rank you no longer cast.
       pet   - Spell Lock and friends live in the PET spellbook, where
               GetSpellCooldown cannot see them at all. They need a walk of
               GetPetActionInfo to find the slot, then GetPetActionCooldown.
       item  - an equipped trinket, by inventory slot (13 or 14). 3.3.5a has
               no dependable GetItemCooldown, so the inventory form is used.

     Editable from Interface -> AddOns -> FycoPvP -> Cooldown Bar, or with
     /fyco track. Loaded by Core.lua at PLAYER_LOGIN.                        ]]

local ADDON, ns = ...
local M = ns:Module("bar")

local GetSpellCooldown         = GetSpellCooldown
local GetSpellInfo             = GetSpellInfo
local GetPetActionInfo         = GetPetActionInfo
local GetPetActionCooldown     = GetPetActionCooldown
local GetInventoryItemCooldown = GetInventoryItemCooldown
local GetInventoryItemTexture  = GetInventoryItemTexture

local NUM_PET_SLOTS = 10

local barDefaults = {
	size = 36, gap = 4, grow = "RIGHT", hideReady = false,
}

-- A reasonable Affliction starting set. Everything is editable.
local trackDefaults = {
	{ kind = "pet",   name = "Spell Lock" },
	{ kind = "spell", name = "Death Coil" },
	{ kind = "spell", name = "Howl of Terror" },
	{ kind = "spell", name = "Shadowfury" },
	{ kind = "spell", name = "Demonic Circle: Teleport" },
	{ kind = "spell", name = "Fel Domination" },
	{ kind = "item",  slot = 13 },
}

local bar
local icons = {}
local panel

----------------------------------------------------------------------
-- cooldown sources
----------------------------------------------------------------------

--- Find a pet ability's action slot by name. The pet bar is rebuilt whenever
--- the pet changes, so this is looked up fresh rather than cached.
local function PetSlot(name)
	for i = 1, NUM_PET_SLOTS do
		local n, _, tex = GetPetActionInfo(i)
		if n == name then return i, tex end
	end
end

--- Returns start, duration, enabled, texture -- or nil when untrackable.
local function Query(entry)
	if entry.kind == "spell" then
		local name, _, tex = GetSpellInfo(entry.name)
		if not name then return nil end
		local start, dur, enabled = GetSpellCooldown(entry.name)
		return start, dur, enabled, tex

	elseif entry.kind == "pet" then
		local slot, tex = PetSlot(entry.name)
		if not slot then return nil end        -- pet dismissed, or wrong pet
		local start, dur, enabled = GetPetActionCooldown(slot)
		return start, dur, enabled, tex

	elseif entry.kind == "item" then
		local tex = GetInventoryItemTexture("player", entry.slot)
		if not tex then return nil end         -- nothing equipped there
		local start, dur, enabled = GetInventoryItemCooldown("player", entry.slot)
		return start, dur, enabled, tex
	end
end

local function Label(entry)
	if entry.kind == "item" then
		return "Trinket " .. (entry.slot == 13 and "1" or "2")
	end
	return entry.name .. (entry.kind == "pet" and " (pet)" or "")
end

----------------------------------------------------------------------
-- frames
----------------------------------------------------------------------

local function MakeIcon(i)
	local cfg = FycoPvPDB.bar
	local f = CreateFrame("Frame", ADDON .. "BarIcon" .. i, bar)
	f:SetWidth(cfg.size)
	f:SetHeight(cfg.size)

	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
	f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)

	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints(f)
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints(f)
	f.cd.noCooldownCount = true   -- we draw our own text; keep OmniCC off it

	f.time = f:CreateFontString(nil, "OVERLAY")
	f.time:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
	f.time:SetPoint("CENTER", f, "CENTER", 0, 0)

	f:Hide()
	return f
end

-- reused each pass: only the shown icons are laid out, and the helper wants
-- them contiguous
local laid = {}

local function Layout()
	local cfg = FycoPvPDB.bar
	local n = 0
	for i = 1, #icons do
		if icons[i]:IsShown() then
			n = n + 1
			icons[i]:SetWidth(cfg.size)
			icons[i]:SetHeight(cfg.size)
			laid[n] = icons[i]
		end
	end

	-- A bar set to grow downward wraps into a second COLUMN rather than a
	-- second row: the same rule, seen sideways.
	local w, h = ns:LayoutIcons(bar, laid, n, cfg.gap, nil, cfg.grow == "DOWN")
	bar:SetWidth(math.max(cfg.size, w))
	bar:SetHeight(math.max(cfg.size, h))
end

local function Build()
	bar = CreateFrame("Frame", ADDON .. "Bar", UIParent)
	bar:SetWidth(barDefaults.size)
	bar:SetHeight(barDefaults.size)
	bar:SetMovable(true)
	bar:EnableMouse(false)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
	bar:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		FycoPvPDB.bar.pos = { p, x, y }
	end)
	local p = FycoPvPDB.bar.pos or { "CENTER", 0, -300 }
	bar:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------

local function Refresh(now)
	if not ns:Enabled("bar") then
		for i = 1, #icons do icons[i]:Hide() end
		return
	end
	local cfg  = FycoPvPDB.bar
	local list = FycoPvPDB.track
	local changed = false

	for i = 1, #list do
		if not icons[i] then
			icons[i] = MakeIcon(i)
			changed = true
		end
		local f = icons[i]
		local start, dur, _, tex = Query(list[i])

		if not tex then
			if f:IsShown() then f:Hide() ; changed = true end
		else
			f.tex:SetTexture(tex)
			-- ignore the global cooldown: everything blinks on the GCD and it
			-- would make the whole bar flicker on every cast
			local onCD = start and start > 0 and dur and dur > 1.5
			local left = onCD and (start + dur - now) or 0

			if onCD and left > 0 then
				if f.cdSet ~= start then
					f.cd:SetCooldown(start, dur)
					f.cdSet = start
				end
				f.tex:SetDesaturated(true)
				f.border:SetTexture(0.75, 0.15, 0.15, 1)
				f.time:SetText(left >= 60 and string.format("%dm", math.ceil(left / 60))
				                            or string.format("%d", left))
			else
				f.cdSet = nil
				f.tex:SetDesaturated(false)
				f.border:SetTexture(0.20, 0.80, 0.30, 1)
				f.time:SetText("")
			end

			local want = not (cfg.hideReady and not onCD)
			if want ~= f:IsShown() then
				if want then f:Show() else f:Hide() end
				changed = true
			end
		end
	end

	-- hide icons whose entry was removed
	for i = #list + 1, #icons do
		if icons[i]:IsShown() then icons[i]:Hide() ; changed = true end
	end

	if changed then Layout() end
end

----------------------------------------------------------------------
-- editing
----------------------------------------------------------------------

--- Add an entry. `what` is a spell name, a spell ID, "pet <name>",
--- "trinket1" or "trinket2".
function ns:BarAdd(what)
	what = (what or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if what == "" then return false, "nothing given" end

	local entry
	local pet = what:match("^[Pp][Ee][Tt]%s+(.+)$")
	if pet then
		entry = { kind = "pet", name = pet }
	elseif what:lower() == "trinket1" then
		entry = { kind = "item", slot = 13 }
	elseif what:lower() == "trinket2" then
		entry = { kind = "item", slot = 14 }
	else
		local id = tonumber(what)
		local name = id and GetSpellInfo(id) or what
		if not name or not GetSpellInfo(name) then
			return false, "no spell called '" .. tostring(what) .. "'"
		end
		entry = { kind = "spell", name = name, id = id }
	end

	table.insert(FycoPvPDB.track, entry)
	if panel and panel.rebuild then panel.rebuild() end
	return true, Label(entry)
end

function ns:BarRemove(index)
	local e = FycoPvPDB.track[index]
	if not e then return false end
	table.remove(FycoPvPDB.track, index)
	local extra = icons[#FycoPvPDB.track + 1]
	if extra then extra:Hide() end
	if panel and panel.rebuild then panel.rebuild() end
	return true, Label(e)
end

function ns:BarList()
	local list = FycoPvPDB.track
	if #list == 0 then ns:Print("  nothing tracked yet") return end
	for i = 1, #list do
		local ok = Query(list[i]) ~= nil
		ns:Print(string.format("  %d. %s%s", i, Label(list[i]),
			ok and "" or " |cffff4444(not available right now)|r"))
	end
end

----------------------------------------------------------------------
-- options sub-panel
----------------------------------------------------------------------

local function BuildPanel()
	panel = CreateFrame("Frame", ADDON .. "BarPanel", UIParent)
	panel.name   = "Cooldown Bar"
	panel.parent = "FycoPvP"

	local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText("Cooldown Bar")

	local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", 16, -42)
	note:SetWidth(540)
	note:SetJustifyH("LEFT")
	note:SetText("Only the cooldowns you pick. Type a spell name or ID; use "
	          .. "'pet Spell Lock' for a pet ability, or 'trinket1' / 'trinket2' "
	          .. "for an equipped trinket. Drag the bar with /fyco lock.")

	local box = CreateFrame("EditBox", ADDON .. "BarAddBox", panel, "InputBoxTemplate")
	box:SetPoint("TOPLEFT", 20, -88)
	box:SetWidth(260)
	box:SetHeight(22)
	box:SetAutoFocus(false)

	local add = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	add:SetPoint("LEFT", box, "RIGHT", 8, 0)
	add:SetWidth(80)
	add:SetHeight(22)
	add:SetText("Add")
	add:SetScript("OnClick", function()
		local ok, msg = ns:BarAdd(box:GetText())
		ns:Print(ok and ("tracking " .. msg) or ("could not add: " .. tostring(msg)))
		if ok then box:SetText("") end
	end)
	box:SetScript("OnEnterPressed", function() add:Click() end)

	local rows = {}
	panel.rebuild = function()
		for i = 1, #rows do rows[i]:Hide() end
		for i = 1, #FycoPvPDB.track do
			local r = rows[i]
			if not r then
				r = CreateFrame("Frame", nil, panel)
				r:SetWidth(360)
				r:SetHeight(22)
				r:SetPoint("TOPLEFT", 20, -120 - (i - 1) * 24)
				r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
				r.text:SetPoint("LEFT", 4, 0)
				r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
				r.del:SetPoint("LEFT", 250, 0)
				r.del:SetWidth(70)
				r.del:SetHeight(20)
				r.del:SetText("Remove")
				rows[i] = r
			end
			r.index = i
			r.text:SetText(i .. ".  " .. Label(FycoPvPDB.track[i]))
			r.del:SetScript("OnClick", function()
				local ok, msg = ns:BarRemove(r.index)
				if ok then ns:Print("stopped tracking " .. msg) end
			end)
			r:Show()
		end
	end

	panel:SetScript("OnShow", panel.rebuild)
	InterfaceOptions_AddCategory(panel)
end

----------------------------------------------------------------------

function M:OnLoad()
	FycoPvPDB.bar = FycoPvPDB.bar or {}
	for k, v in pairs(barDefaults) do
		if FycoPvPDB.bar[k] == nil then FycoPvPDB.bar[k] = v end
	end
	if not FycoPvPDB.track then
		FycoPvPDB.track = {}
		for i = 1, #trackDefaults do
			FycoPvPDB.track[i] = trackDefaults[i]
		end
	end

	Build()
	BuildPanel()

	ns:OnTick(function(now) Refresh(now) end)

	ns:Subscribe("ToggleLock", function()
		if bar:IsMouseEnabled() then
			bar:EnableMouse(false)
		else
			bar:EnableMouse(true)
			-- force every icon visible so the bar can be found and dragged
			for i = 1, #FycoPvPDB.track do
				if not icons[i] then icons[i] = MakeIcon(i) end
				if not icons[i].tex:GetTexture() then
					icons[i].tex:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowBolt")
				end
				icons[i]:Show()
			end
			Layout()
			ns:Print("cooldown bar unlocked - drag it, then |cffffff00/fyco lock|r again")
		end
	end)
end
