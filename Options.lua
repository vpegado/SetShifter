-- SetShifter settings panel (Options > AddOns > SetShifter, or /setshifter)

local _, ns = ...

local PAD = 16
local ROW_HEIGHT = 32
local MOUNT_ICON = "Interface\\Icons\\Ability_Mount_RidingHorse"
local FISHING_ICON = "Interface\\Icons\\Trade_Fishing"

local panel = CreateFrame("Frame")
panel.name = "SetShifter"
panel:Hide()

---------------------------------------------------------------------------
-- Set picker popup (one shared list, built from plain buttons so it works
-- across clients without depending on a dropdown library)
---------------------------------------------------------------------------
local picker = CreateFrame("Frame", nil, panel, "BackdropTemplate")
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
panel:SetScript("OnHide", function() picker:Hide() end)

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

local enable = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
enable:SetSize(24, 24)
enable:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -4, -12)
local enableLabel = enable:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
enableLabel:SetPoint("LEFT", enable, "RIGHT", 2, 0)
enableLabel:SetText("Swap gear automatically when changing form")
enable:SetScript("OnClick", function(self)
	ns.db.enabled = self:GetChecked() and true or false
end)

local minimap = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
minimap:SetSize(24, 24)
minimap:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", 0, -2)
local minimapLabel = minimap:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
minimapLabel:SetPoint("LEFT", minimap, "RIGHT", 2, 0)
minimapLabel:SetText("Show minimap button")
minimap:SetScript("OnClick", function(self)
	ns.db.minimap.hide = not self:GetChecked()
	ns.UpdateMinimapButton()
end)

---------------------------------------------------------------------------
-- Set rows: icon, name, set picker and Equip button
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

---------------------------------------------------------------------------
-- Fishing: Fishing set, Fish key and bobber hooking
---------------------------------------------------------------------------
local fishHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
fishHeader:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 4, -16)
fishHeader:SetText("Fishing")

local fishRow = NewRow()
fishRow:SetPoint("TOPLEFT", fishHeader, "BOTTOMLEFT", 0, -8)

-- The key row lines up with the Fishing row above it: the label under the
-- row's name, the key button under its set button, the hint under Equip.
local keyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
keyButton:SetPoint("TOPLEFT", fishRow.set, "BOTTOMLEFT", 0, -6)
keyButton:SetPoint("TOPRIGHT", fishRow.set, "BOTTOMRIGHT", 0, -6)
keyButton:SetHeight(22)
keyButton:RegisterForClicks("AnyUp")

local keyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
-- Same width and gap as the row's name column, so its left edge matches.
keyLabel:SetPoint("RIGHT", keyButton, "LEFT", -8, 0)
keyLabel:SetWidth(170)
keyLabel:SetJustifyH("LEFT")
keyLabel:SetText("Fish key")

local keyHint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
keyHint:SetPoint("LEFT", keyButton, "RIGHT", 6, 0)
keyHint:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
keyHint:SetJustifyH("LEFT")

local KEY_HINT = "Click, then press a key. Right-click to unbind."
local keyMessage -- shown instead of the hint after a change, e.g. a conflict

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
	return GetBindingText and GetBindingText(key) or key
end

local function StopListening()
	keyButton.listening = false
	keyButton:EnableKeyboard(false)
end

local function UpdateKeyButton()
	if keyButton.listening then
		keyButton:SetText("|cffffd100Press a key...|r")
		keyHint:SetText("Escape to cancel.")
		return
	end
	local key = GetBindingKey(ns.FISH_BINDING)
	keyButton:SetText(key and KeyText(key) or "|cff888888Not bound|r")
	keyButton:SetEnabled(not InCombatLockdown())
	if InCombatLockdown() then
		keyHint:SetText("Key bindings can't be changed in combat.")
	else
		keyHint:SetText(keyMessage or KEY_HINT)
	end
end

local function SaveKeyBindings()
	SaveBindings(GetCurrentBindingSet())
end

local function BindFishKey(key)
	if InCombatLockdown() then return end
	local previous = GetBindingAction(key)
	-- One Fish key: remove the old one(s) first.
	for _, old in ipairs({ GetBindingKey(ns.FISH_BINDING) }) do
		SetBinding(old)
	end
	if SetBinding(key, ns.FISH_BINDING) then
		SaveKeyBindings()
		if previous and previous ~= "" and previous ~= ns.FISH_BINDING then
			local name = GetBindingName and GetBindingName(previous) or previous
			keyMessage = ("|cffff9933%s was bound to %s.|r"):format(KeyText(key), name)
		else
			keyMessage = nil
		end
	else
		keyMessage = "|cffff5555Couldn't bind " .. KeyText(key) .. ".|r"
	end
end

local function UnbindFishKey()
	if InCombatLockdown() then return end
	for _, old in ipairs({ GetBindingKey(ns.FISH_BINDING) }) do
		SetBinding(old)
	end
	SaveKeyBindings()
	keyMessage = nil
end

keyButton:SetScript("OnClick", function(self, mouseButton)
	if self.listening then
		if MOUSE_KEYS[mouseButton] then
			StopListening()
			BindFishKey(ModifierPrefix() .. MOUSE_KEYS[mouseButton])
		else
			StopListening() -- left or right click cancels
		end
	elseif mouseButton == "RightButton" then
		UnbindFishKey()
	elseif mouseButton == "LeftButton" then
		self.listening = true
		keyMessage = nil
		self:EnableKeyboard(true)
		self:SetPropagateKeyboardInput(false)
	end
	UpdateKeyButton()
end)

keyButton:SetScript("OnKeyDown", function(self, key)
	if not self.listening or MODIFIER_KEYS[key] then return end
	StopListening()
	if key ~= "ESCAPE" then
		BindFishKey(ModifierPrefix() .. key)
	end
	UpdateKeyButton()
end)

keyButton:SetScript("OnHide", function(self)
	if self.listening then StopListening() end
end)

local hook = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
hook:SetSize(24, 24)
hook:SetPoint("TOPLEFT", fishRow, "BOTTOMLEFT", -4, -40)
local hookLabel = hook:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
hookLabel:SetPoint("LEFT", hook, "RIGHT", 2, 0)
hookLabel:SetText("Fish key also hooks the bobber")
local hookNote = hook:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
hookNote:SetPoint("TOPLEFT", hookLabel, "BOTTOMLEFT", 0, -2)
hookNote:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
hookNote:SetJustifyH("LEFT")
hookNote:SetText("While the bobber is out, press the Fish key again to hook the fish. "
	.. "Widens the interact range while fishing; your interact settings go back when you stop.")
hook:SetScript("OnClick", function(self)
	ns.SetHookBobber(self:GetChecked() and true or false)
end)

local formsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
formsHeader:SetPoint("TOPLEFT", hook, "BOTTOMLEFT", 4, -28)
formsHeader:SetText("Sets")

local noSets = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
noSets:SetPoint("LEFT", formsHeader, "RIGHT", 12, 0)
noSets:SetText("No sets yet. Create them in the Equipment Manager on the character panel.")

---------------------------------------------------------------------------
-- Form rows
---------------------------------------------------------------------------
local rows = {}

local function Row(i)
	local row = rows[i]
	if row then return row end
	row = NewRow()
	row:SetPoint("TOPLEFT", formsHeader, "BOTTOMLEFT", 0, -8 - (i - 1) * ROW_HEIGHT)
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

function Refresh()
	if not ns.db then return end
	enable:SetChecked(ns.db.enabled)
	minimap:SetChecked(not ns.db.minimap.hide)
	hook:SetChecked(ns.db.hookBobber)
	UpdateKeyButton()
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
end
ns.RefreshOptions = function() if panel:IsVisible() then Refresh() end end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
panel:SetScript("OnShow", Refresh)

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
	if event == "PLAYER_REGEN_DISABLED" and keyButton.listening then StopListening() end
	ns.RefreshOptions()
end)

local category
if Settings and Settings.RegisterCanvasLayoutCategory then
	category = Settings.RegisterCanvasLayoutCategory(panel, "SetShifter")
	Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(panel)
end

function ns.OpenOptions()
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end
