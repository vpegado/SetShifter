-- SetShifter minimap button: shows the icon of the current set, opens the
-- settings on click, and can be dragged around the minimap edge.

local _, ns = ...

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local button = CreateFrame("Button", "SetShifterMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("AnyUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
button:Hide()

local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(20, 20)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetPoint("TOPLEFT", 7, -5)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

---------------------------------------------------------------------------
-- Current set
---------------------------------------------------------------------------

-- The set to show: the one mapped to the current form if it's equipped,
-- otherwise any equipped set, otherwise the mapped set (e.g. still waiting
-- for combat to end). Returns name, icon; or nil if there is none.
local function CurrentSet()
	if not C_EquipmentSet then return end
	local mapped = ns.db and ns.db.map[ns.CurrentKey()]
	local equipped, mappedIcon
	for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs()) do
		local name, setIcon, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(id)
		if name == mapped then
			if isEquipped then return name, setIcon end
			mappedIcon = setIcon
		elseif isEquipped and not equipped then
			equipped = { name, setIcon }
		end
	end
	if equipped then return equipped[1], equipped[2] end
	if mappedIcon then return mapped, mappedIcon end
end

local function FormIcon()
	local index = GetShapeshiftForm()
	if index and index > 0 then
		return (GetShapeshiftFormInfo(index))
	end
end

local function UpdateIcon()
	local _, setIcon = CurrentSet()
	icon:SetTexture(setIcon or FormIcon() or FALLBACK_ICON)
end

---------------------------------------------------------------------------
-- Position around the minimap edge
---------------------------------------------------------------------------

local function UpdatePosition()
	local angle = math.rad(ns.db.minimap.angle)
	local x, y = math.cos(angle), math.sin(angle)
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		-- Push out to the corners of a square minimap.
		x = math.max(-1, math.min(1, x * 1.41421))
		y = math.max(-1, math.min(1, y * 1.41421))
	end
	local rx = Minimap:GetWidth() / 2 + 5
	local ry = Minimap:GetHeight() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x * rx, y * ry)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale
	ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
	UpdatePosition()
end

button:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", OnDragUpdate)
	GameTooltip:Hide()
end)
button:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil)
end)

---------------------------------------------------------------------------
-- Click and tooltip
---------------------------------------------------------------------------

button:SetScript("OnClick", function()
	ns.OpenOptions()
end)

button:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("SetShifter")
	GameTooltip:AddDoubleLine("Form:", ns.CurrentFormKey() .. (ns.IsMounted() and " (mounted)" or "")
		.. (ns.IsFishing() and " (fishing)" or ""),
		nil, nil, nil, 1, 1, 1)
	GameTooltip:AddDoubleLine("Set:", CurrentSet() or "|cff888888None|r", nil, nil, nil, 1, 1, 1)
	if not ns.db.enabled then
		GameTooltip:AddLine("Automatic swapping is off.", 1, 0.3, 0.3)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click to open settings. Drag to move.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end)
button:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

---------------------------------------------------------------------------
-- Show / hide
---------------------------------------------------------------------------

function ns.UpdateMinimapButton()
	if not ns.db then return end
	if ns.db.minimap.hide then
		button:Hide()
	else
		UpdatePosition()
		UpdateIcon()
		button:Show()
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		ns.UpdateMinimapButton()

		self:RegisterEvent("EQUIPMENT_SETS_CHANGED")
		self:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
		self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		self:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		if not pcall(self.RegisterEvent, self, "PLAYER_MOUNT_DISPLAY_CHANGED") then
			self:RegisterUnitEvent("UNIT_AURA", "player")
		end
	elseif button:IsShown() then
		UpdateIcon()
	end
end)
