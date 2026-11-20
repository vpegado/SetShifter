-- SetShifter: equip an Equipment Manager set whenever you change shapeshift form.
--
-- Map forms to sets in Options > AddOns > SetShifter (or /setshifter).
-- "Default" (no form) is a form too, so map it to switch back when you leave one.
-- "Mounted" can have a set too; it takes priority over your form while you
-- are mounted, and your form's set goes back on when you dismount.
-- "Fishing" can have a set too: the Fish key (Key Bindings > AddOns >
-- SetShifter) equips it on the first press and casts Fishing on the next.
-- Your form's set goes back on when you enter combat, mount, shift into a form,
-- or stop fishing for a while.
--
-- Works for any class with a stance bar: druid forms, warrior stances, etc.
--
-- Armor can't be changed in combat. In combat, only the set's weapons are
-- swapped; the full set is applied as soon as combat ends (for whatever form
-- you're in at that moment).

local ADDON, ns = ...

local NO_FORM = "Default"
ns.NO_FORM = NO_FORM
local MOUNTED = "Mounted"
ns.MOUNTED = MOUNTED
local FISHING = "Fishing"
ns.FISHING = FISHING

local FISHING_SPELL_ID = 7620
local FISH_BINDING = "CLICK SetShifterFishButton:LeftButton"
ns.FISH_BINDING = FISH_BINDING
BINDING_HEADER_SETSHIFTER = "SetShifter"
_G["BINDING_NAME_" .. FISH_BINDING] = "Fish (equip Fishing set, then cast)"

local db
local lastKey
local pending = false

-- Fishing mode: on while you're using the Fishing set.
local fishing = false
local fishingForm     -- form you were in when fishing started
local returnSet       -- set worn before fishing; used if your form has no set
local fishTimerGen = 0 -- bumped to cancel a pending fishing timeout
local lastFishEquip = -math.huge -- when the Fish key last equipped the set

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

function ns.IsFishing()
	return fishing
end

-- The key whose set should be worn right now: "Fishing" in fishing mode,
-- "Mounted" while mounted (if a set is mapped to it), otherwise the current
-- form.
function ns.CurrentKey()
	if fishing and db and db.map[FISHING] then return FISHING end
	if db and db.map[MOUNTED] and ns.IsMounted() then return MOUNTED end
	return ns.CurrentFormKey()
end

-- Warriors are always in a stance, so "Default" (no form) never applies.
local _, playerClass = UnitClass("player")
local HAS_NO_FORM = playerClass ~= "WARRIOR"

-- All forms the character knows: { {key=, icon=}, ... }, "Default" first.
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

-- Equip a set by name. `label` names what it's for, in messages.
local function EquipSet(setName, label, verbose)
	local id = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID(setName)
	if not id then
		Print(("Set \"%s\" (for %s) no longer exists."):format(setName, label))
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

local function EquipForForm(formKey, verbose)
	local setName = db.map[formKey]
	if not setName then
		if verbose then Print("No set mapped to " .. formKey .. ".") end
		return
	end
	EquipSet(setName, formKey, verbose)
end
ns.EquipForForm = EquipForForm

-- Equip what should be worn right now: the set for the current form, mount
-- or fishing mode. Right after fishing, if that state has no set, put back
-- the set that was worn before fishing.
local function EquipCurrent()
	local key = ns.CurrentKey()
	lastKey = key
	if db.map[key] then
		EquipForForm(key)
	elseif returnSet and not fishing then
		EquipSet(returnSet, "after fishing")
	end
	if not fishing and not InCombat() then returnSet = nil end
end

---------------------------------------------------------------------------
-- Fishing
---------------------------------------------------------------------------

local function FishingSetID()
	local name = db.map[FISHING]
	return name and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID(name)
end

-- The Fish key clicks this secure button. Spells can only be cast from a
-- secure button, and an equip and a cast can't happen in the same press
-- (the pole isn't in your hand yet). So the first press equips the Fishing
-- set and the next press casts.
local fishButton = CreateFrame("Button", "SetShifterFishButton", UIParent, "SecureActionButtonTemplate")
fishButton:SetAttribute("type", "spell")
fishButton:Hide()

---------------------------------------------------------------------------
-- Bobber hooking (optional, db.hookBobber)
--
-- While the bobber is out, the Fish key is rebound to "Interact with Target"
-- and the soft-interact range is widened so the bobber becomes the interact
-- target: press the Fish key again on the splash to hook the fish. The
-- interact settings are changed when fishing starts and put back exactly as
-- they were when fishing ends.
---------------------------------------------------------------------------

local HOOK_CVARS = {
	SoftTargetInteract = "3",           -- on for mouse/keyboard and gamepad
	SoftTargetInteractRange = "30",     -- yards; the bobber lands up to ~20 away
	SoftTargetInteractRangeIsHard = "0",
	SoftTargetIconGameObject = "1",     -- show the interact icon over the bobber
	SoftTargetIconInteract = "1",
}

local bindingOwner = CreateFrame("Frame")
local pendingInteractOff = false -- clear the key override once combat ends

local function ApplyHookCVars()
	if db.savedCVars then return end -- already applied
	local saved = {}
	for name, value in pairs(HOOK_CVARS) do
		local old = C_CVar.GetCVar(name)
		if old ~= nil then -- skip CVars this client doesn't have
			saved[name] = old
			C_CVar.SetCVar(name, value)
		end
	end
	-- Kept in saved variables so they can be put back even after a crash.
	db.savedCVars = saved
end

local function RestoreHookCVars()
	local saved = db and db.savedCVars
	if not saved then return end
	for name, value in pairs(saved) do
		C_CVar.SetCVar(name, value)
	end
	db.savedCVars = nil
end

-- Point the Fish key at "Interact with Target" (on) or back at casting (off).
-- Bindings can't change in combat; turning it off then waits for combat to end.
local function SetInteractMode(on)
	if InCombatLockdown() then
		pendingInteractOff = pendingInteractOff or not on
		return
	end
	ClearOverrideBindings(bindingOwner)
	if on then
		for _, key in ipairs({ GetBindingKey(FISH_BINDING) }) do
			SetOverrideBinding(bindingOwner, true, key, "INTERACTTARGET")
		end
	end
	pendingInteractOff = false
end

local function StopHooking()
	SetInteractMode(false)
	RestoreHookCVars()
end
ns.StopHooking = StopHooking

---------------------------------------------------------------------------
-- Fishing mode
---------------------------------------------------------------------------

local fishSetUsed = false -- whether this fishing session put on the Fishing set

function ns.FishingConfigured()
	return db.map[FISHING] ~= nil or db.hookBobber
end

local function ExitFishing()
	if not fishing then return end
	fishing = false
	fishTimerGen = fishTimerGen + 1
	lastFishEquip = -math.huge
	StopHooking()
	if fishSetUsed then
		EquipCurrent()
	else
		lastKey = ns.CurrentKey()
	end
	if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
	if ns.RefreshOptions then ns.RefreshOptions() end
end
ns.ExitFishing = ExitFishing

-- Leave fishing mode after db.fishingTimeout seconds without a Fishing cast.
local function ScheduleFishingTimeout()
	fishTimerGen = fishTimerGen + 1
	local timeout = db.fishingTimeout
	if not timeout or timeout <= 0 then return end
	local gen = fishTimerGen
	C_Timer.After(timeout, function()
		if gen == fishTimerGen and fishing and not UnitChannelInfo("player") then
			ExitFishing()
		end
	end)
end

local function EnterFishing()
	if fishing then
		ScheduleFishingTimeout()
		return
	end
	fishSetUsed = db.map[FISHING] ~= nil
	local formKey = ns.CurrentFormKey()
	returnSet = nil
	if fishSetUsed then
		-- Remember the set worn now, for forms that have no set of their own.
		for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
			local name, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(id)
			if isEquipped and name ~= db.map[FISHING] then
				returnSet = name
				break
			end
		end
		if not db.map[formKey] and not returnSet then
			Print(("Map a set to %s so your gear goes back on after fishing."):format(formKey))
		end
	end
	fishing = true
	fishingForm = formKey
	lastKey = ns.CurrentKey()
	if db.hookBobber then ApplyHookCVars() end
	ScheduleFishingTimeout()
	if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
	if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Turn bobber hooking on or off. Takes effect right away if you're fishing.
function ns.SetHookBobber(on)
	db.hookBobber = on
	if not fishing then return end
	if on then
		ApplyHookCVars()
		if UnitChannelInfo("player") then SetInteractMode(true) end
	else
		StopHooking()
	end
end

-- PreClick runs before the secure action. Attributes can only be changed out
-- of combat, which is fine: you can't start fishing in combat anyway.
fishButton:SetScript("PreClick", function(self)
	if InCombatLockdown() then return end
	local id = FishingSetID()
	local isEquipped = true
	if id then
		isEquipped = select(4, C_EquipmentSet.GetEquipmentSetInfo(id))
	end
	-- After an equip, the next press casts even if part of the set didn't go
	-- on (e.g. an item in the bank), so a missing item can't block fishing.
	if not isEquipped and GetTime() - lastFishEquip > 3 then
		lastFishEquip = GetTime()
		self:SetAttribute("type", "macro")
		self:SetAttribute("macrotext", "/equipset " .. db.map[FISHING])
	else
		self:SetAttribute("type", "spell")
	end
	if ns.FishingConfigured() then EnterFishing() end
end)

-- React on only one edge of the key press, so one press doesn't cast twice.
local function UpdateFishClicks()
	if InCombatLockdown() then return end
	if GetCVarBool("ActionButtonUseKeyDown") then
		fishButton:RegisterForClicks("AnyDown")
	else
		fishButton:RegisterForClicks("AnyUp")
	end
end

local function IsFishingSpell(spellID)
	local name = spellID and GetSpellNameCompat(spellID)
	return name ~= nil and name == fishButton:GetAttribute("spell")
end

local function OnStateChanged()
	if fishing then
		local formKey = ns.CurrentFormKey()
		if formKey == NO_FORM and fishingForm ~= NO_FORM then
			-- Casting Fishing drops you out of your form (e.g. Cat Form).
			-- That's part of fishing, so keep fishing; shifting back into a
			-- form from here ends it.
			fishingForm = NO_FORM
		elseif ns.IsMounted() or formKey ~= fishingForm then
			-- Mounting or shifting into a form ends fishing.
			ExitFishing()
			return
		end
	end
	local key = ns.CurrentKey()
	if key == lastKey then return end
	lastKey = key
	if db.enabled then EquipCurrent() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("CVAR_UPDATE")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
-- Mount changes: use the dedicated event where the client has it, otherwise
-- watch the player's auras (mounts are auras in Classic).
if not pcall(frame.RegisterEvent, frame, "PLAYER_MOUNT_DISPLAY_CHANGED") then
	frame:RegisterUnitEvent("UNIT_AURA", "player")
end

local scheduled = false
frame:SetScript("OnEvent", function(_, event, arg1, _, arg3)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		SetShifterDB = SetShifterDB or {}
		db = SetShifterDB
		db.sets = nil -- v1.0 gear snapshots; replaced by Equipment Manager sets
		db.map = db.map or {}
		-- The no-form state was "Caster" up to v1.2 and "No form" up to v1.4.
		for _, old in ipairs({ "No form", "Caster" }) do
			if db.map[old] and not db.map[NO_FORM] then
				db.map[NO_FORM] = db.map[old]
			end
			db.map[old] = nil
		end
		if db.enabled == nil then db.enabled = true end
		db.minimap = db.minimap or {}
		db.minimap.angle = db.minimap.angle or 225
		if db.fishingTimeout == nil then db.fishingTimeout = 60 end
		if db.hookBobber == nil then db.hookBobber = false end
		ns.db = db
		-- Left over from a crash or disconnect while fishing: put the
		-- player's interact settings back.
		RestoreHookCVars()
		frame:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		fishButton:SetAttribute("spell", GetSpellNameCompat(FISHING_SPELL_ID))
		UpdateFishClicks()
	elseif event == "PLAYER_LOGOUT" then
		-- Save the player's own interact settings, not the fishing ones.
		RestoreHookCVars()
	elseif event == "PLAYER_ENTERING_WORLD" then
		if fishing then
			-- Zoning (e.g. hearthing) while fishing: put your gear back.
			ExitFishing()
		else
			-- Record the state we log in with; don't swap gear on login.
			lastKey = ns.CurrentKey()
		end
	elseif event == "CVAR_UPDATE" then
		if arg1 == "ActionButtonUseKeyDown" or arg1 == "ACTION_BUTTON_USE_KEY_DOWN" then
			UpdateFishClicks()
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		if IsFishingSpell(arg3) then
			-- Casting Fishing any way (spellbook, action bar) counts as fishing.
			if ns.FishingConfigured() then EnterFishing() end
			if fishing then
				fishTimerGen = fishTimerGen + 1 -- no timeout while the line is out
				if db.hookBobber then SetInteractMode(true) end
			end
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if fishing then
			SetInteractMode(false) -- the Fish key casts again
			ScheduleFishingTimeout()
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Weapons back right away; the rest of the set after combat.
		ExitFishing()
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
		if pending then
			EquipCurrent()
		end
		if pendingInteractOff then SetInteractMode(false) end
		UpdateFishClicks() -- in case the setting changed during combat
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
	Print(("%s: %s"):format(FISHING, db.map[FISHING] or "|cff888888none|r"))
	Print("Current form: " .. ns.CurrentFormKey() .. (ns.IsMounted() and " (mounted)" or "")
		.. (fishing and " (fishing)" or "") .. (db.enabled and "" or " (auto-swap OFF)"))
	local key = GetBindingKey(FISH_BINDING)
	Print("Fish key: " .. (key or "|cff888888not bound|r (Key Bindings > AddOns > SetShifter)"))
end

SLASH_SETSHIFTER1 = "/setshifter"
SLASH_SETSHIFTER2 = "/sshift"
SlashCmdList.SETSHIFTER = function(msg)
	local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "fishtimeout" then
		local seconds = tonumber(arg)
		if seconds and seconds >= 0 then
			db.fishingTimeout = math.floor(seconds)
		end
		Print(db.fishingTimeout > 0
			and ("Fishing ends after %d seconds without a cast."):format(db.fishingTimeout)
			or "Fishing only ends on combat, mounting, changing form or /setshifter stopfishing.")
	elseif cmd == "hook" then
		ns.SetHookBobber(not db.hookBobber)
		Print("Bobber hooking " .. (db.hookBobber and "on." or "off."))
		if ns.RefreshOptions then ns.RefreshOptions() end
	elseif cmd == "stopfishing" then
		if fishing then ExitFishing() else Print("Not fishing.") end
	elseif cmd == "list" then
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
		Print("/setshifter hook - turn bobber hooking with the Fish key on or off")
		Print("/setshifter stopfishing - stop fishing and put your gear and settings back now")
		Print("/setshifter fishtimeout <seconds> - end fishing after this long without a cast (0 = never)")
	end
end
