--[[ FycoPvP - Modules/Buffs.lua
     Watches a list of buffs you want up and shows ONLY the ones that are
     missing. When everything is running the frame hides entirely, so it costs
     no screen space in the normal case.

     Silent by design: this is a passive reminder, not an alert. The Alerts
     module owns anything that should interrupt you.

     Addons cannot cast, so this cannot reapply anything for you -- casting is
     protected and only ever runs from a real keypress. Reporting what is
     missing is the most an addon is allowed to do.

     Entries match BY NAME, because a buff's rank changes as you level while
     the name does not. `kind = "pet"` is the one special case: it checks for a
     live pet rather than an aura.
     Loaded by Core.lua at PLAYER_LOGIN.                                      ]]

local ADDON, ns = ...
local M = ns:Module("buffs")

local UnitBuff     = UnitBuff
local UnitExists   = UnitExists
local GetSpellInfo = GetSpellInfo

local MAX_SHOWN = 8

local frameDefaults = { size = 34, gap = 6 }

-- Affliction PvP defaults. Everything here is editable.
local watchDefaults = {
	{ name = "Fel Armor" },
	{ name = "Soul Link" },
	{ name = "Soulstone Resurrection" },
	{ kind = "pet" },
}

local anchor
local icons = {}
local panel

----------------------------------------------------------------------
-- checks
----------------------------------------------------------------------

local function HasBuff(name)
	for i = 1, 40 do
		local n = UnitBuff("player", i)
		if not n then return false end
		if n == name then return true end
	end
	return false
end

local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- Returns satisfied, icon texture, label.
local function Check(entry)
	if entry.kind == "pet" then
		return UnitExists("pet"), "Interface\\Icons\\Spell_Shadow_SummonFelHunter", "Pet"
	end
	local n, _, tex = GetSpellInfo(entry.name)
	-- A name the client cannot resolve returns no texture, which drew an empty
	-- red box with nothing in it. Show a question mark instead so the slot is
	-- always legible, and OnLoad says which entry it is.
	return HasBuff(entry.name), tex or UNKNOWN_ICON, (n or entry.name)
end

local function Label(entry)
	if entry.kind == "pet" then return "Pet" end
	return entry.name
end

----------------------------------------------------------------------
-- frames
----------------------------------------------------------------------

local function MakeIcon(i)
	local cfg = FycoPvPDB.buffs
	local f = CreateFrame("Frame", ADDON .. "BuffMissing" .. i, anchor)
	f:SetWidth(cfg.size)
	f:SetHeight(cfg.size)

	f.border = f:CreateTexture(nil, "BACKGROUND")
	f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
	f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
	f.border:SetTexture(0.85, 0.20, 0.20, 1)

	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints(f)
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.tex:SetDesaturated(true)      -- missing, so it reads as "off"

	-- No name label. A FontString with no width auto-sizes to its text, so
	-- "Soulstone Resurrection" stretched far past its 34px icon and printed
	-- across both neighbours. The icon alone is enough; /fyco buff lists names.

	f:Hide()
	return f
end

local function Build()
	anchor = CreateFrame("Frame", ADDON .. "Buffs", UIParent)
	anchor:SetWidth(frameDefaults.size)
	anchor:SetHeight(frameDefaults.size)
	anchor:SetMovable(true)
	anchor:EnableMouse(false)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		FycoPvPDB.buffs.pos = { p, x, y }
	end)
	local p = FycoPvPDB.buffs.pos or { "CENTER", -300, 0 }
	anchor:SetPoint(p[1], UIParent, p[1], p[2], p[3])
	anchor:Hide()
end

local function Layout(n)
	local cfg = FycoPvPDB.buffs
	for i = 1, n do
		icons[i]:SetWidth(cfg.size)
		icons[i]:SetHeight(cfg.size)
	end
	local w, h = ns:LayoutIcons(anchor, icons, n, cfg.gap)
	anchor:SetWidth(math.max(cfg.size, w))
	anchor:SetHeight(math.max(cfg.size, h))
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------

local function Refresh()
	if not ns:Enabled("buffs") then
		anchor:Hide()
		return
	end
	if anchor.preview then return end

	local list = FycoPvPDB.watch
	local n = 0

	for i = 1, #list do
		if n >= MAX_SHOWN then break end
		local ok, tex, label = Check(list[i])
		if not ok then
			n = n + 1
			if not icons[n] then icons[n] = MakeIcon(n) end
			local f = icons[n]
			f.tex:SetTexture(tex)
			f:Show()
		end
	end

	for i = n + 1, #icons do icons[i]:Hide() end

	-- nothing missing means nothing on screen at all
	if n == 0 then
		anchor:Hide()
	else
		Layout(n)
		anchor:Show()
	end
end

----------------------------------------------------------------------
-- editing
----------------------------------------------------------------------

function ns:BuffAdd(what)
	what = (what or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if what == "" then return false, "nothing given" end

	local entry
	if what:lower() == "pet" then
		entry = { kind = "pet" }
	else
		local id = tonumber(what)
		local name = id and GetSpellInfo(id) or what
		if not name or not GetSpellInfo(name) then
			return false, "no spell called '" .. tostring(what) .. "'"
		end
		entry = { name = name }
	end
	table.insert(FycoPvPDB.watch, entry)
	if panel and panel.rebuild then panel.rebuild() end
	return true, Label(entry)
end

function ns:BuffRemove(index)
	local e = FycoPvPDB.watch[index]
	if not e then return false end
	table.remove(FycoPvPDB.watch, index)
	for i = 1, #icons do icons[i]:Hide() end
	if panel and panel.rebuild then panel.rebuild() end
	return true, Label(e)
end

function ns:BuffList()
	local list = FycoPvPDB.watch
	if #list == 0 then ns:Print("  watching nothing") return end
	for i = 1, #list do
		local ok = Check(list[i])
		ns:Print(string.format("  %d. %-26s %s", i, Label(list[i]),
			ok and "|cff44ff44up|r" or "|cffff4444MISSING|r"))
	end
end

----------------------------------------------------------------------
-- options sub-panel
----------------------------------------------------------------------

local function BuildPanel()
	panel = CreateFrame("Frame", ADDON .. "BuffsPanel", UIParent)
	panel.name   = "Buffs"
	panel.parent = "FycoPvP"

	local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText("Missing Buffs")

	local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", 16, -42)
	note:SetWidth(460)
	note:SetJustifyH("LEFT")
	note:SetText("Shows only what is MISSING, and hides completely when "
	          .. "everything is up. Type a buff name or spell ID, or 'pet' to "
	          .. "watch for a summoned pet. Silent by design.")

	local box = CreateFrame("EditBox", ADDON .. "BuffAddBox", panel, "InputBoxTemplate")
	box:SetPoint("TOPLEFT", 20, -96)
	box:SetWidth(240)
	box:SetHeight(22)
	box:SetAutoFocus(false)

	local add = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	add:SetPoint("LEFT", box, "RIGHT", 8, 0)
	add:SetWidth(80)
	add:SetHeight(22)
	add:SetText("Add")
	add:SetScript("OnClick", function()
		local ok, msg = ns:BuffAdd(box:GetText())
		ns:Print(ok and ("watching " .. msg) or ("could not add: " .. tostring(msg)))
		if ok then box:SetText("") end
	end)
	box:SetScript("OnEnterPressed", function() add:Click() end)

	local rows = {}
	panel.rebuild = function()
		for i = 1, #rows do rows[i]:Hide() end
		for i = 1, #FycoPvPDB.watch do
			local r = rows[i]
			if not r then
				r = CreateFrame("Frame", nil, panel)
				r:SetWidth(360)
				r:SetHeight(22)
				r:SetPoint("TOPLEFT", 20, -128 - (i - 1) * 24)
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
			r.text:SetText(i .. ".  " .. Label(FycoPvPDB.watch[i]))
			r.del:SetScript("OnClick", function()
				local ok, msg = ns:BuffRemove(r.index)
				if ok then ns:Print("stopped watching " .. msg) end
			end)
			r:Show()
		end
	end

	panel:SetScript("OnShow", panel.rebuild)
	InterfaceOptions_AddCategory(panel)
end

----------------------------------------------------------------------

function M:OnLoad()
	FycoPvPDB.buffs = FycoPvPDB.buffs or {}
	for k, v in pairs(frameDefaults) do
		if FycoPvPDB.buffs[k] == nil then FycoPvPDB.buffs[k] = v end
	end
	if not FycoPvPDB.watch then
		FycoPvPDB.watch = {}
		for i = 1, #watchDefaults do FycoPvPDB.watch[i] = watchDefaults[i] end
	end

	Build()
	BuildPanel()

	-- Report anything the client cannot resolve. With no names on the icons an
	-- unresolvable entry would otherwise be a silent question mark.
	local bad = {}
	for i = 1, #FycoPvPDB.watch do
		local e = FycoPvPDB.watch[i]
		if e.name and not GetSpellInfo(e.name) then
			table.insert(bad, i .. ". " .. e.name)
		end
	end
	if #bad > 0 then
		ns:Print("|cffff4444these watched buffs are not known to the client:|r")
		for i = 1, #bad do ns:Print("  " .. bad[i]) end
		ns:Print("check the spelling, or remove with |cffffff00/fyco unbuff <number>|r")
	end

	ns:Subscribe("UnitAura", function(unit)
		if unit == "player" then Refresh() end
	end)
	ns:On("UNIT_PET", Refresh)
	ns:On("PLAYER_ENTERING_WORLD", Refresh)

	-- a slow tick catches anything the events miss, such as a soulstone expiring
	ns:OnTick(function(now)
		if not ns._buffSweep or now - ns._buffSweep > 1 then
			ns._buffSweep = now
			Refresh()
		end
	end)

	ns:Subscribe("ToggleLock", function()
		if anchor:IsMouseEnabled() then
			anchor:EnableMouse(false)
			anchor.preview = nil
			Refresh()
		else
			anchor:EnableMouse(true)
			anchor.preview = true
			-- show every watched entry so the frame can be found and dragged
			local n = math.min(#FycoPvPDB.watch, MAX_SHOWN)
			if n == 0 then n = 1 end
			for i = 1, n do
				if not icons[i] then icons[i] = MakeIcon(i) end
				local e = FycoPvPDB.watch[i] or { kind = "pet" }
				local _, tex, label = Check(e)
				icons[i].tex:SetTexture(tex)
				icons[i]:Show()
			end
			for i = n + 1, #icons do icons[i]:Hide() end
			Layout(n)
			anchor:Show()
			ns:Print("missing-buff frame unlocked - drag it, then |cffffff00/fyco lock|r again")
		end
	end)

	Refresh()
end
