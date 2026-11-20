-- SetShifter druid extras:
--
-- Travel key: one key for getting around. In water it casts Aquatic Form,
-- outdoors on land your "outdoors" form (Travel Form by default), anywhere
-- else your "elsewhere" form (Cat Form by default). Pick the forms in the
-- settings; bind the key there or in Key Bindings > AddOns > SetShifter.
--
-- Water hint: when you start swimming, the Aquatic Form button on the
-- stance bar lights up and a short message names your Travel key. Addons
-- can't shift you into a form by themselves; every cast needs a key press.

local _, ns = ...

local TRAVEL_BINDING = "CLICK SetShifterTravelButton:LeftButton"
ns.TRAVEL_BINDING = TRAVEL_BINDING
_G["BINDING_NAME_" .. TRAVEL_BINDING] = "Travel form (Aquatic Form in water)"

local _, playerClass = UnitClass("player")
ns.IS_DRUID = playerClass == "DRUID"
if not ns.IS_DRUID then return end

local AQUATIC_FORM_ID = 1066
local TRAVEL_FORM_ID = 783
local CAT_FORM_ID = 768

-- The two land choices: db.travelOutdoors / db.travelElsewhere hold a form
-- name, false for none, or nil for the default.
local DEFAULT_FORM = { Outdoors = TRAVEL_FORM_ID, Elsewhere = CAT_FORM_ID }

function ns.TravelForm(which)
	local value = ns.db["travel" .. which]
	if value == false then return nil end
	return value or ns.GetSpellName(DEFAULT_FORM[which])
end

-- Forms on the stance bar, by name: { [name] = stance bar index }.
local function KnownForms()
	local known = {}
	for i = 1, GetNumShapeshiftForms() do
		local _, _, _, spellID = GetShapeshiftFormInfo(i)
		local name = spellID and ns.GetSpellName(spellID)
		if name then known[name] = i end
	end
	return known
end
ns.KnownFormIndexes = KnownForms

---------------------------------------------------------------------------
-- Travel key
---------------------------------------------------------------------------

local button = CreateFrame("Button", "SetShifterTravelButton", UIParent, "SecureActionButtonTemplate")
button:SetAttribute("type", "macro")
button:Hide()
ns.keyButtons[#ns.keyButtons + 1] = button

local hasMacro = false
local pendingUpdate = false

local function BuildMacro()
	local known = KnownForms()
	local parts = {}
	local aquatic = ns.GetSpellName(AQUATIC_FORM_ID)
	if known[aquatic] then parts[#parts + 1] = "[swimming] " .. aquatic end
	local outdoors = ns.TravelForm("Outdoors")
	if outdoors and known[outdoors] then parts[#parts + 1] = "[outdoors] " .. outdoors end
	local elsewhere = ns.TravelForm("Elsewhere")
	if elsewhere and known[elsewhere] then parts[#parts + 1] = elsewhere end
	if #parts == 0 then return nil end
	return "/cast " .. table.concat(parts, "; ")
end

-- The macro can only change out of combat; changes made in combat wait.
function ns.UpdateTravelButton()
	if not ns.db then return end
	if InCombatLockdown() then
		pendingUpdate = true
		return
	end
	pendingUpdate = false
	local macro = BuildMacro()
	hasMacro = macro ~= nil
	button:SetAttribute("macrotext", macro or "")
end

function ns.SetTravelForm(which, value)
	ns.db["travel" .. which] = value
	ns.UpdateTravelButton()
end

button:SetScript("PreClick", function()
	if not hasMacro then
		ns.Print("No travel forms known yet. Pick them in the settings (/setshifter).")
	end
end)

---------------------------------------------------------------------------
-- Water hint
---------------------------------------------------------------------------

local glow
local wasSwimming = false

local function StanceButton(index)
	return _G["StanceButton" .. index] or _G["ShapeshiftButton" .. index]
end

local function HideHint()
	if glow then
		glow.anim:Stop()
		glow:Hide()
	end
end

-- A pulsing ring around a stance bar button. Anchored to it rather than
-- parented, so it never touches the (protected) stance bar itself.
local function GlowOn(target)
	if not glow then
		glow = CreateFrame("Frame", nil, UIParent)
		glow:SetFrameStrata("HIGH")
		local ring = glow:CreateTexture(nil, "OVERLAY")
		ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		ring:SetBlendMode("ADD")
		ring:SetVertexColor(0.4, 0.8, 1)
		ring:SetAllPoints()
		glow.anim = glow:CreateAnimationGroup()
		glow.anim:SetLooping("BOUNCE")
		local fade = glow.anim:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.35)
		fade:SetDuration(0.6)
	end
	local size = target:GetWidth() * 1.8
	glow:ClearAllPoints()
	glow:SetPoint("CENTER", target, "CENTER")
	glow:SetSize(size, size)
	glow:Show()
	glow.anim:Play()
end

local function ShowHint()
	local index = KnownForms()[ns.GetSpellName(AQUATIC_FORM_ID)]
	if not index or GetShapeshiftForm() == index then return end
	local target = StanceButton(index)
	if target and target:IsVisible() then GlowOn(target) end
	local key = GetBindingKey(TRAVEL_BINDING)
	local text = key
		and ("Aquatic Form: press %s"):format(GetBindingText and GetBindingText(key) or key)
		or "Aquatic Form is ready"
	if UIErrorsFrame then UIErrorsFrame:AddMessage(text, 0.4, 0.8, 1) end
end

-- There's no event for starting or stopping swimming, so check a few times
-- a second. IsSwimming() is a cheap flag lookup.
local function CheckSwimming()
	local swimming = IsSwimming() and true or false
	if swimming == wasSwimming then return end
	wasSwimming = swimming
	if swimming and ns.db.waterHint then
		ShowHint()
	else
		HideHint()
	end
end

function ns.SetWaterHint(on)
	ns.db.waterHint = on
	if not on then HideHint() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if ns.db.waterHint == nil then ns.db.waterHint = true end
		ns.UpdateTravelButton()
		C_Timer.NewTicker(0.25, CheckSwimming)
	elseif event == "UPDATE_SHAPESHIFT_FORMS" then
		-- A form was learned or lost.
		ns.UpdateTravelButton()
	elseif event == "UPDATE_SHAPESHIFT_FORM" then
		-- Shifted (e.g. into Aquatic Form): the hint has done its job.
		HideHint()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingUpdate then ns.UpdateTravelButton() end
	end
end)
