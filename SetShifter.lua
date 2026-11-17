-- SetShifter: equip an Equipment Manager set whenever you change shapeshift form.
--
-- Map forms to sets in Options > AddOns > SetShifter (or /setshifter).
-- "Caster" (no form) is a form too, so map it to switch back when you leave one.
--
-- Armor can't be changed in combat; a swap requested in combat is applied as
-- soon as combat ends (for whatever form you're in at that moment).

local ADDON, ns = ...

local CASTER = "Caster"
ns.CASTER = CASTER

local db
local lastForm
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
	if not index or index == 0 then return CASTER end
	local _, _, _, spellID = GetShapeshiftFormInfo(index)
	local name = spellID and GetSpellNameCompat(spellID)
	return name or ("Form " .. index)
end

function ns.CurrentFormKey()
	return FormKey(GetShapeshiftForm())
end

-- All forms the character knows: { {key=, icon=}, ... }, Caster first.
function ns.KnownForms()
	local forms = { { key = CASTER } }
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
		pending = true
		if verbose then Print("In combat; will equip after combat.") end
		return
	end
	pending = false

	local _, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(id)
	if not isEquipped then
		C_EquipmentSet.UseEquipmentSet(id)
	end
end
ns.EquipForForm = EquipForForm

local function OnFormChanged()
	local form = ns.CurrentFormKey()
	if form == lastForm then return end
	lastForm = form
	if db.enabled then EquipForForm(form) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

local scheduled = false
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		SetShifterDB = SetShifterDB or {}
		db = SetShifterDB
		db.sets = nil -- v1.0 gear snapshots; replaced by Equipment Manager sets
		db.map = db.map or {}
		if db.enabled == nil then db.enabled = true end
		ns.db = db
		frame:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Record the form we log in with; don't swap gear on login.
		lastForm = ns.CurrentFormKey()
	elseif event == "UPDATE_SHAPESHIFT_FORM" then
		-- This event fires in bursts; coalesce into a single check.
		if not scheduled then
			scheduled = true
			C_Timer.After(0.1, function()
				scheduled = false
				OnFormChanged()
			end)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending and db.enabled then
			lastForm = ns.CurrentFormKey()
			EquipForForm(lastForm)
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
	Print("Current form: " .. ns.CurrentFormKey() .. (db.enabled and "" or " (auto-swap OFF)"))
end

SLASH_SETSHIFTER1 = "/setshifter"
SLASH_SETSHIFTER2 = "/sshift"
SlashCmdList.SETSHIFTER = function(msg)
	local cmd = msg:match("^%s*(%S*)"):lower()
	if cmd == "list" then
		ListMappings()
	elseif cmd == "equip" then
		EquipForForm(ns.CurrentFormKey(), true)
	elseif cmd == "on" or cmd == "off" then
		db.enabled = (cmd == "on")
		Print("Automatic swapping " .. (db.enabled and "enabled." or "disabled."))
		if ns.RefreshOptions then ns.RefreshOptions() end
	elseif cmd == "" or cmd == "options" or cmd == "config" then
		ns.OpenOptions()
	else
		Print("/setshifter - open settings")
		Print("/setshifter list - show form -> set mappings")
		Print("/setshifter equip - equip the set for your current form now")
		Print("/setshifter on | off - toggle automatic swapping")
	end
end
