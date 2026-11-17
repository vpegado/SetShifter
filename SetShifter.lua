-- SetShifter: equip an Equipment Manager set whenever you change shapeshift form.
--
-- Map forms to sets in Options > AddOns > SetShifter (or /setshifter).
-- "No form" is a form too, so map it to switch back when you leave one.
-- "Mounted" can have a set too; it takes priority over your form while you
-- are mounted, and your form's set goes back on when you dismount.
--
-- Works for any class with a stance bar: druid forms, warrior stances, etc.
--
-- Armor can't be changed in combat. In combat, only the set's weapons are
-- swapped; the full set is applied as soon as combat ends (for whatever form
-- you're in at that moment).

local ADDON, ns = ...

local NO_FORM = "No form"
ns.NO_FORM = NO_FORM
local MOUNTED = "Mounted"
ns.MOUNTED = MOUNTED

local db
local lastKey
local pending = false

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66dd66SetShifter|r: " .. msg)
end
ns.Print = Print

local function GetSpellNameCompat(id)
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(id)
	end
	return (GetSpellInfo(id))
end

local function InCombat()
	return InCombatLockdown() or UnitAffectingCombat("player")
end

-- Key for a form index. Keyed by spell name rather than index, since indexes
-- shift with talents (e.g. Moonkin Form).
local function FormKey(index)
	if not index or index == 0 then return NO_FORM end
	local _, _, _, spellID = GetShapeshiftFormInfo(index)
	local name = spellID and GetSpellNameCompat(spellID)
	return name or ("Form " .. index)
end

function ns.CurrentFormKey()
	return FormKey(GetShapeshiftForm())
end

function ns.IsMounted()
	return IsMounted and IsMounted() or false
end

-- The key whose set should be worn right now: "Mounted" while mounted (if a
-- set is mapped to it), otherwise the current form.
function ns.CurrentKey()
	if db and db.map[MOUNTED] and ns.IsMounted() then return MOUNTED end
	return ns.CurrentFormKey()
end

-- Warriors are always in a stance, so "No form" never applies.
local _, playerClass = UnitClass("player")
local HAS_NO_FORM = playerClass ~= "WARRIOR"

-- All forms the character knows: { {key=, icon=}, ... }, "No form" first.
function ns.KnownForms()
	local forms = HAS_NO_FORM and { { key = NO_FORM } } or {}
	for i = 1, GetNumShapeshiftForms() do
		local icon = GetShapeshiftFormInfo(i)
		forms[#forms + 1] = { key = FormKey(i), icon = icon }
	end
	return forms
end

-- Names of all Equipment Manager sets, sorted.
function ns.SetNames()
	local names = {}
	if C_EquipmentSet then
		for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
			names[#names + 1] = C_EquipmentSet.GetEquipmentSetInfo(id)
		end
	end
	table.sort(names)
	return names
end

function ns.SetExists(name)
	return C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID(name) ~= nil
end

---------------------------------------------------------------------------
-- Equipping
---------------------------------------------------------------------------

-- Weapon slots can be changed in combat (armor can't).
local WEAPON_SLOTS = { 16, 17, 18 } -- main hand, off hand, ranged

-- Equip just the weapons from a set. Order matters: main hand first, so a
-- one-hander replaces a two-hander before the shield goes on.
local function EquipWeapons(id)
	local itemIDs = C_EquipmentSet.GetItemIDs(id)
	if not itemIDs then return end
	for _, slot in ipairs(WEAPON_SLOTS) do
		local itemID = itemIDs[slot]
		-- Empty/ignored slots come back as nil or small sentinel values.
		if itemID and itemID > 1 and GetInventoryItemID("player", slot) ~= itemID then
			EquipItemByName(itemID, slot)
		end
	end
end

local function EquipForForm(formKey, verbose)
	local setName = db.map[formKey]
	if not setName then
		if verbose then Print("No set mapped to " .. formKey .. ".") end
		return
	end
	local id = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID(setName)
	if not id then
		Print(("Set \"%s\" (for %s) no longer exists."):format(setName, formKey))
		return
	end
	if InCombat() then
		-- Swap weapons now (e.g. a shield for Defensive Stance); the rest of
		-- the set goes on when combat ends.
		EquipWeapons(id)
		pending = true
		if verbose then Print("In combat; swapped weapons, the rest will equip after combat.") end
		return
	end
	pending = false

	local _, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(id)
	if not isEquipped then
		C_EquipmentSet.UseEquipmentSet(id)
	end
end
ns.EquipForForm = EquipForForm

local function OnStateChanged()
	local key = ns.CurrentKey()
	if key == lastKey then return end
	lastKey = key
	if db.enabled then EquipForForm(key) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Mount changes: use the dedicated event where the client has it, otherwise
-- watch the player's auras (mounts are auras in Classic).
if not pcall(frame.RegisterEvent, frame, "PLAYER_MOUNT_DISPLAY_CHANGED") then
	frame:RegisterUnitEvent("UNIT_AURA", "player")
end

local scheduled = false
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		SetShifterDB = SetShifterDB or {}
		db = SetShifterDB
		db.sets = nil -- v1.0 gear snapshots; replaced by Equipment Manager sets
		db.map = db.map or {}
		-- v1.2 and earlier called the no-form state "Caster".
		if db.map.Caster and not db.map[NO_FORM] then
			db.map[NO_FORM] = db.map.Caster
		end
		db.map.Caster = nil
		if db.enabled == nil then db.enabled = true end
		db.minimap = db.minimap or {}
		db.minimap.angle = db.minimap.angle or 225
		ns.db = db
		frame:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Record the state we log in with; don't swap gear on login.
		lastKey = ns.CurrentKey()
	elseif event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_MOUNT_DISPLAY_CHANGED"
		or event == "UNIT_AURA" then
		-- This event fires in bursts; coalesce into a single check.
		if not scheduled then
			scheduled = true
			C_Timer.After(0.1, function()
				scheduled = false
				OnStateChanged()
			end)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending and db.enabled then
			lastKey = ns.CurrentKey()
			EquipForForm(lastKey)
		end
	end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function ListMappings()
	for _, form in ipairs(ns.KnownForms()) do
		local set = db.map[form.key]
		Print(("%s: %s"):format(form.key, set or "|cff888888none|r"))
	end
	Print(("%s: %s"):format(MOUNTED, db.map[MOUNTED] or "|cff888888none|r"))
	Print("Current form: " .. ns.CurrentFormKey() .. (ns.IsMounted() and " (mounted)" or "")
		.. (db.enabled and "" or " (auto-swap OFF)"))
end

SLASH_SETSHIFTER1 = "/setshifter"
SLASH_SETSHIFTER2 = "/sshift"
SlashCmdList.SETSHIFTER = function(msg)
	local cmd = msg:match("^%s*(%S*)"):lower()
	if cmd == "list" then
		ListMappings()
	elseif cmd == "equip" then
		EquipForForm(ns.CurrentKey(), true)
	elseif cmd == "on" or cmd == "off" then
		db.enabled = (cmd == "on")
		Print("Automatic swapping " .. (db.enabled and "enabled." or "disabled."))
		if ns.RefreshOptions then ns.RefreshOptions() end
	elseif cmd == "minimap" then
		db.minimap.hide = not db.minimap.hide
		ns.UpdateMinimapButton()
		Print("Minimap button " .. (db.minimap.hide and "hidden." or "shown."))
		if ns.RefreshOptions then ns.RefreshOptions() end
	elseif cmd == "" or cmd == "options" or cmd == "config" then
		ns.OpenOptions()
	else
		Print("/setshifter - open settings")
		Print("/setshifter list - show form -> set mappings")
		Print("/setshifter equip - equip the set for your current form (or mount) now")
		Print("/setshifter on | off - toggle automatic swapping")
		Print("/setshifter minimap - show or hide the minimap button")
	end
end
