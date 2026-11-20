-- SetShifter settings panel (Options > AddOns > SetShifter, or /setshifter)

local _, ns = ...

local PAD = 16
local ROW_HEIGHT = 32
local MOUNT_ICON = "Interface\\Icons\\Ability_Mount_RidingHorse"
local FISHING_ICON = "Interface\\Icons\\Trade_Fishing"
local AQUATIC_ICON = "Interface\\Icons\\Ability_Druid_AquaticForm"

-- `canvas` is what the Settings window shows. The content lives in `panel`,
-- inside a scroll frame, so long form lists (a druid with every form) still
-- fit. Without the scroll template, the content goes straight on the canvas.
local canvas = CreateFrame("Frame")
canvas.name = "SetShifter"
canvas:Hide()

local scroll, panel
do
	local ok, frame = pcall(CreateFrame, "ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
	if ok and frame then
		scroll = frame
		scroll:SetPoint("TOPLEFT", 0, -4)
		scroll:SetPoint("BOTTOMRIGHT", -26, 4)
		panel = CreateFrame("Frame", nil, scroll)
		panel:SetSize(1, 1)
		scroll:SetScrollChild(panel)
		scroll:SetScript("OnSizeChanged", function(_, width) panel:SetWidth(width) end)
	else
		panel = CreateFrame("Frame", nil, canvas)
		panel:SetAllPoints()
	end
end

---------------------------------------------------------------------------
-- Picker popup (one shared list, built from plain buttons so it works
-- across clients without depending on a dropdown library). It lives on the
-- canvas, not in the scroll frame, so the scroll frame doesn't clip it.
---------------------------------------------------------------------------
local picker = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
picker:SetFrameStrata("FULLSCREEN_DIALOG")
picker:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
picker:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
picker:EnableMouse(true)
picker:Hide()
picker.buttons = {}

local function PickerButton(i)
	local b = picker.buttons[i]
	if b then return b end
	b = CreateFrame("Button", nil, picker)
	b:SetHeight(18)
	b:SetPoint("LEFT", picker, "LEFT", 8, 0)
	b:SetPoint("RIGHT", picker, "RIGHT", -8, 0)
	b:SetPoint("TOP", picker, "TOP", 0, -8 - (i - 1) * 18)
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT")
	fs:SetJustifyH("LEFT")
	b.text = fs
	picker.buttons[i] = b
	return b
end

-- options = { {value=, label=}, ... }; onPick(value)
local function OpenPicker(anchor, options, onPick)
	if picker:IsShown() and picker.anchor == anchor then
		picker:Hide()
		return
	end
	for _, b in ipairs(picker.buttons) do b:Hide() end
	local width = anchor:GetWidth()
	for i, opt in ipairs(options) do
		local b = PickerButton(i)
		b.text:SetText(opt.label)
		width = math.max(width, b.text:GetStringWidth() + 24)
		b:SetScript("OnClick", function()
			picker:Hide()
			onPick(opt.value)
		end)
		b:Show()
	end
	picker.anchor = anchor
	picker:ClearAllPoints()
	picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	picker:SetSize(width, #options * 18 + 16)
	picker:Show()
end
canvas:SetScript("OnHide", function() picker:Hide() end)
if scroll then scroll:HookScript("OnVerticalScroll", function() picker:Hide() end) end

---------------------------------------------------------------------------
-- Header
---------------------------------------------------------------------------
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", PAD, -PAD)
title:SetText("SetShifter")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
subtitle:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Choose an Equipment Manager set for each form or stance. It is equipped when you shift into it. "
	.. "A Mounted set takes priority while you are mounted. "
	.. "The Fishing set is put on by the Fish key (set it below). "
	.. "In combat, only weapons are swapped; the rest of the set goes on when combat ends.")

local function CheckBox(anchor, x, y, label, onClick)
	local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	box:SetSize(24, 24)
	box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
	box.label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
	box.label:SetText(label)
	box:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	return box
end

local enable = CheckBox(subtitle, -4, -12, "Swap gear automatically when changing form",
	function(on) ns.db.enabled = on end)

local minimap = CheckBox(enable, 0, -2, "Show minimap button", function(on)
	ns.db.minimap.hide = not on
	ns.UpdateMinimapButton()
end)

local messages = CheckBox(minimap, 0, -2, "Show on-screen hints (e.g. \"press the Fish key again\")",
	function(on) ns.db.showMessages = on end)

local function SectionHeader(anchor, x, y, text)
	local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
	header:SetText(text)
	return header
end

---------------------------------------------------------------------------
-- Rows: icon, name, a wide button (set picker, key, form) and an Equip
-- button. Every section uses them, so the columns line up down the panel.
---------------------------------------------------------------------------
local function NewRow()
	local row = CreateFrame("Frame", nil, panel)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(24, 24)
	row.icon:SetPoint("LEFT")

	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
	row.name:SetWidth(170)
	row.name:SetJustifyH("LEFT")

	row.set = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.set:SetSize(200, 22)
	row.set:SetPoint("LEFT", row.name, "RIGHT", 8, 0)

	row.equip = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.equip:SetSize(70, 22)
	row.equip:SetPoint("LEFT", row.set, "RIGHT", 6, 0)
	row.equip:SetText("Equip")
	return row
end

-- A row that sits right under `above` (y: extra vertical offset).
local function RowBelow(above, y)
	local row = NewRow()
	row:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, y or 0)
	return row
end

-- A row with small grey text in place of the Equip button.
local function NoteRow(above, y)
	local row = RowBelow(above, y)
	row.equip:Hide()
	row.note = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.note:SetPoint("LEFT", row.set, "RIGHT", 6, 0)
	row.note:SetPoint("RIGHT", row, "RIGHT")
	row.note:SetJustifyH("LEFT")
	return row
end

---------------------------------------------------------------------------
-- Key binding rows: click the button, then press a key (or mouse button 3-5)
-- to bind it; right-click to unbind. Same binding as in Key Bindings.
---------------------------------------------------------------------------
local KEY_HINT = "Click to set, right-click to clear."

-- Keys that are only modifiers; wait for the real key.
local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, LMETA = true, RMETA = true,
}
-- Mouse buttons that can be bound (left and right are for the button itself).
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

-- Modifiers held right now, in the order WoW writes them ("ALT-CTRL-SHIFT-").
local function ModifierPrefix()
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "") .. (IsMetaKeyDown and IsMetaKeyDown() and "META-" or "")
end

local function KeyText(key)
	return ns.KeyName(key)
end

local keyRows = {}

local function UpdateKeyRow(row)
	local button = row.set
	if button.listening then
		button:SetText("|cffffd100Press a key...|r")
		row.note:SetText("Escape to cancel.")
		return
	end
	local key = GetBindingKey(row.binding)
	button:SetText(key and KeyText(key) or "|cff888888Not bound|r")
	button:SetEnabled(not InCombatLockdown())
	if InCombatLockdown() then
		row.note:SetText("Can't change keys in combat.")
	else
		row.note:SetText(row.message or KEY_HINT)
	end
end

local function StopListening(row)
	row.set.listening = false
	row.set:EnableKeyboard(false)
end

local function Unbind(row)
	for _, old in ipairs({ GetBindingKey(row.binding) }) do
		SetBinding(old)
	end
end

local function Bind(row, key)
	if InCombatLockdown() then return end
	local previous = GetBindingAction(key)
	Unbind(row) -- one key per action: remove the old one first
	if SetBinding(key, row.binding) then
		SaveBindings(GetCurrentBindingSet())
		if previous and previous ~= "" and previous ~= row.binding then
			local name = GetBindingName and GetBindingName(previous) or previous
			row.message = ("|cffff9933%s was bound to %s.|r"):format(KeyText(key), name)
		else
			row.message = nil
		end
	else
		row.message = "|cffff5555Couldn't bind " .. KeyText(key) .. ".|r"
	end
end

local function KeyRow(above, y, label, binding, icon)
	local row = NoteRow(above, y)
	row.binding = binding
	row.name:SetText(label)
	if icon then row.icon:SetTexture(icon) end
	local button = row.set
	button:RegisterForClicks("AnyUp")

	button:SetScript("OnClick", function(self, mouseButton)
		if self.listening then
			StopListening(row)
			if MOUSE_KEYS[mouseButton] then
				Bind(row, ModifierPrefix() .. MOUSE_KEYS[mouseButton])
			end -- a left or right click cancels
		elseif mouseButton == "RightButton" then
			if not InCombatLockdown() then
				Unbind(row)
				SaveBindings(GetCurrentBindingSet())
				row.message = nil
			end
		elseif mouseButton == "LeftButton" then
			-- Only one row listens at a time.
			for _, other in ipairs(keyRows) do
				if other.set.listening then StopListening(other); UpdateKeyRow(other) end
			end
			self.listening = true
			row.message = nil
			self:EnableKeyboard(true)
			self:SetPropagateKeyboardInput(false)
		end
		UpdateKeyRow(row)
	end)

	button:SetScript("OnKeyDown", function(self, key)
		if not self.listening or MODIFIER_KEYS[key] then return end
		StopListening(row)
		if key ~= "ESCAPE" then
			Bind(row, ModifierPrefix() .. key)
		end
		UpdateKeyRow(row)
	end)

	button:SetScript("OnHide", function(self)
		if self.listening then StopListening(row) end
	end)

	keyRows[#keyRows + 1] = row
	return row
end

---------------------------------------------------------------------------
-- Fishing: Fishing set, Fish key and bobber hooking
---------------------------------------------------------------------------
local fishHeader = SectionHeader(messages, 4, -16, "Fishing")

local fishRow = RowBelow(fishHeader, -4)
local fishKeyRow = KeyRow(fishRow, 0, "Fish key", ns.FISH_BINDING)

local hook = CheckBox(fishKeyRow, -4, -2, "Fish key also hooks the bobber",
	function(on) ns.SetHookBobber(on) end)
local hookNote = hook:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
hookNote:SetPoint("TOPLEFT", hook.label, "BOTTOMLEFT", 0, -2)
hookNote:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
hookNote:SetJustifyH("LEFT")
hookNote:SetText("Press the Fish key again on the splash to hook. Interact settings are restored after fishing.")

local lastAboveSets, setsOffset = hook, -24

---------------------------------------------------------------------------
-- Travel (druids): Travel key, its land forms, and the water hint
---------------------------------------------------------------------------
local travelKeyRow, landRows, waterHint
if ns.IS_DRUID then
	local travelHeader = SectionHeader(hook, 4, -24, "Travel")

	travelKeyRow = KeyRow(travelHeader, -4, "Travel key", ns.TRAVEL_BINDING, AQUATIC_ICON)

	-- Which form the Travel key casts on land. In water it's Aquatic Form.
	landRows = {}
	local above = travelKeyRow
	for _, land in ipairs({
		{ which = "Outdoors", label = "Outdoors on land", note = "In water: Aquatic Form." },
		{ which = "Elsewhere", label = "Anywhere else", note = "Indoors, or if Outdoors is None." },
	}) do
		local row = NoteRow(above)
		row.which = land.which
		row.name:SetText(land.label)
		row.note:SetText(land.note)
		landRows[#landRows + 1] = row
		above = row
	end

	waterHint = CheckBox(above, -4, -2, "Highlight Aquatic Form when you start swimming",
		function(on) ns.SetWaterHint(on) end)
	lastAboveSets, setsOffset = waterHint, -16
end

---------------------------------------------------------------------------
-- Sets: one row per form, plus Mounted
---------------------------------------------------------------------------
local formsHeader = SectionHeader(lastAboveSets, 4, setsOffset, "Sets")

local noSets = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
noSets:SetPoint("LEFT", formsHeader, "RIGHT", 12, 0)
noSets:SetText("No sets yet. Create them in the Equipment Manager on the character panel.")

local rows = {}

local function Row(i)
	local row = rows[i]
	if row then return row end
	row = NewRow()
	row:SetPoint("TOPLEFT", formsHeader, "BOTTOMLEFT", 0, -4 - (i - 1) * ROW_HEIGHT)
	rows[i] = row
	return row
end

local Refresh

local function SetLabel(setName)
	if not setName then return "|cff888888None|r" end
	if not ns.SetExists(setName) then return setName .. " |cffff5555(missing)|r" end
	return setName
end

local function ShowRow(row, key, icon, known)
	if icon then
		row.icon:SetTexture(icon)
	else
		SetPortraitTexture(row.icon, "player")
	end
	row.icon:SetDesaturated(not known)

	local current = ns.CurrentKey() == key
	row.name:SetText((current and "|cff66dd66" or (known and "" or "|cff888888"))
		.. key .. (current and " (current)" or "") .. ((current or not known) and "|r" or ""))

	local mapped = ns.db.map[key]
	row.set:SetText(SetLabel(mapped))
	row.set:SetScript("OnClick", function(self)
		local options = { { value = false, label = "|cff888888None|r" } }
		for _, name in ipairs(ns.SetNames()) do
			options[#options + 1] = { value = name, label = name }
		end
		OpenPicker(self, options, function(value)
			ns.db.map[key] = value or nil
			Refresh()
		end)
	end)

	row.equip:SetEnabled(mapped ~= nil and ns.SetExists(mapped))
	row.equip:SetScript("OnClick", function() ns.EquipForForm(key, true) end)
	row:Show()
end

-- The land-form rows of the Travel section.
local function ShowLandRow(row)
	local formIcons = {}
	for _, form in ipairs(ns.KnownForms()) do
		if form.icon then formIcons[form.key] = form.icon end
	end
	local chosen = ns.TravelForm(row.which)
	row.icon:SetTexture(chosen and formIcons[chosen] or nil)
	if not chosen then
		row.set:SetText("|cff888888None|r")
	elseif formIcons[chosen] then
		row.set:SetText(chosen)
	else
		row.set:SetText(chosen .. " |cff888888(not learned)|r")
	end
	row.set:SetScript("OnClick", function(self)
		local options = { { value = false, label = "|cff888888None|r" } }
		for _, form in ipairs(ns.KnownForms()) do
			if form.key ~= ns.NO_FORM then
				options[#options + 1] = { value = form.key, label = form.key }
			end
		end
		OpenPicker(self, options, function(value)
			ns.SetTravelForm(row.which, value)
			Refresh()
		end)
	end)
end

-- Grow the scroll child to fit everything, once the layout has settled.
local function UpdateHeight(lowest)
	if not scroll then return end
	C_Timer.After(0, function()
		local top, bottom = panel:GetTop(), lowest:GetBottom()
		if top and bottom then panel:SetHeight(top - bottom + PAD) end
	end)
end

function Refresh()
	if not ns.db then return end
	if scroll then panel:SetWidth(scroll:GetWidth()) end
	enable:SetChecked(ns.db.enabled)
	minimap:SetChecked(not ns.db.minimap.hide)
	messages:SetChecked(ns.db.showMessages ~= false)
	hook:SetChecked(ns.db.hookBobber)
	for _, row in ipairs(keyRows) do UpdateKeyRow(row) end
	if landRows then
		for _, row in ipairs(landRows) do ShowLandRow(row) end
		waterHint:SetChecked(ns.db.waterHint)
	end
	noSets:SetShown(#ns.SetNames() == 0)

	for _, row in ipairs(rows) do row:Hide() end
	local i, seen = 0, {}
	for _, form in ipairs(ns.KnownForms()) do
		i = i + 1
		seen[form.key] = true
		ShowRow(Row(i), form.key, form.icon, true)
	end
	i = i + 1
	seen[ns.MOUNTED] = true
	ShowRow(Row(i), ns.MOUNTED, MOUNT_ICON, true)
	seen[ns.FISHING] = true
	ShowRow(fishRow, ns.FISHING, FISHING_ICON, true)
	-- Mappings for forms this character doesn't currently have (e.g. a talent
	-- form after a respec) stay listed so they can be cleared.
	local extra = {}
	for key in pairs(ns.db.map) do
		if not seen[key] then extra[#extra + 1] = key end
	end
	table.sort(extra)
	for _, key in ipairs(extra) do
		i = i + 1
		ShowRow(Row(i), key, "Interface\\Icons\\INV_Misc_QuestionMark", false)
	end
	UpdateHeight(Row(i))
end
ns.RefreshOptions = function() if canvas:IsVisible() then Refresh() end end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
canvas:SetScript("OnShow", Refresh)

local events = CreateFrame("Frame")
events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
if not pcall(events.RegisterEvent, events, "PLAYER_MOUNT_DISPLAY_CHANGED") then
	events:RegisterUnitEvent("UNIT_AURA", "player")
end
events:SetScript("OnEvent", function(_, event)
	-- Combat starts: stop waiting for a key (bindings can't change in combat).
	if event == "PLAYER_REGEN_DISABLED" then
		for _, row in ipairs(keyRows) do
			if row.set.listening then StopListening(row) end
		end
	end
	ns.RefreshOptions()
end)

local category
if Settings and Settings.RegisterCanvasLayoutCategory then
	category = Settings.RegisterCanvasLayoutCategory(canvas, "SetShifter")
	Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(canvas)
end

function ns.OpenOptions()
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(canvas)
		InterfaceOptionsFrame_OpenToCategory(canvas)
	end
end
