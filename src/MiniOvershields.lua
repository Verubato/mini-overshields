local _, addon = ...
---@type MiniFramework
local mini = addon.Framework
---@type Scheduler
local scheduler = addon.Scheduler
---@type Container[]
local containers = {}
local eventsFrame

---@param container Container
local function ReanchorOverAbsorbGlow(container)
	local overAbsorbGlow = container.OverAbsorbGlow
	local texture = container.Absorb:GetStatusBarTexture()

	-- https://github.com/Gethe/wow-ui-source/blob/a29cc452e9c3d86b40ff7cc1024eb36ed8306cdd/Interface/AddOns/Blizzard_UnitFrame/Mainline/UnitFrame.lua#L29
	overAbsorbGlow:ClearAllPoints()
	overAbsorbGlow:SetPoint("TOP", texture, "TOP", 0, 0)
	overAbsorbGlow:SetPoint("BOTTOM", texture, "BOTTOM", 0, 0)
	overAbsorbGlow:SetPoint("LEFT", texture, "LEFT", -7, 0)
end

---@param unitFrame table
---@param healthBar table
---@param overAbsorbGlow table?
---@return Container
local function EnsureContainer(unitFrame, healthBar, overAbsorbGlow)
	if containers[unitFrame] then
		return containers[unitFrame]
	end

	local absorb = CreateFrame("StatusBar", nil, healthBar)
	absorb:SetAllPoints(healthBar)
	absorb:SetReverseFill(true)
	absorb:SetStatusBarTexture("Interface\\RaidFrame\\Shield-Overlay")
	-- don't draw above the health bar
	absorb:SetFrameLevel(healthBar:GetFrameLevel())

	-- not sure why this is happening for some users, perpaps another addon doing it
	local strata = healthBar:GetFrameStrata()
	strata = mini:IsSecret(strata) and "LOW" or strata

	absorb:SetFrameStrata(strata)
	absorb:SetStatusBarColor(1, 1, 1, 0.5)
	absorb:Hide()

	local texture = absorb:GetStatusBarTexture()
	texture:SetTexture("Interface\\RaidFrame\\Shield-Overlay", "REPEAT", "REPEAT")
	texture:SetHorizTile(true)
	texture:SetVertTile(true)
	-- draw behind other artifacts such as the frame selection border
	texture:SetDrawLayer("ARTWORK", 1)

	local container = {
		UnitFrame = unitFrame,
		HealthBar = healthBar,
		Absorb = absorb,
		OverAbsorbGlow = overAbsorbGlow,
	}
	containers[unitFrame] = container

	if overAbsorbGlow then
		scheduler:RunWhenCombatEnds(function()
			ReanchorOverAbsorbGlow(container)
		end)
	end

	return container
end

---@param container Container
---@param unit string
local function Update(container, unit)
	local absorb = container.Absorb
	local maxHealth = UnitHealthMax(unit) or 0
	local totalAbsorbs = UnitGetTotalAbsorbs(unit)

	absorb:SetMinMaxValues(0, maxHealth)
	absorb:SetValue(totalAbsorbs)

	local glow = container.OverAbsorbGlow

	if not glow then
		absorb:Show()
		return
	end

	-- if the glow is visible then we know there is an overshield!
	if glow:IsVisible() then
		absorb:Show()
	else
		absorb:Hide()
	end
end

---@return table? unitFrame
---@return table? healthBar
---@return table? overAbsorbGlow
local function GetBlizzardUnitHealthBar(unit)
	if unit == "player" then
		if PlayerFrame and PlayerFrame.healthbar then
			return PlayerFrame, PlayerFrame.healthbar, PlayerFrame.overAbsorbGlow
		end
		if
			PlayerFrame
			and PlayerFrame.PlayerFrameContent
			and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
			and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar
		then
			return PlayerFrame,
				PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar,
				PlayerFrame.overAbsorbGlow
		end
	elseif unit == "target" then
		if TargetFrame and TargetFrame.healthbar then
			return TargetFrame, TargetFrame.healthbar, TargetFrame.overAbsorbGlow
		end
		if
			TargetFrame
			and TargetFrame.TargetFrameContent
			and TargetFrame.TargetFrameContent.TargetFrameContentMain
			and TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBar
		then
			return TargetFrame,
				TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBar,
				TargetFrame.overAbsorbGlow
		end
	elseif unit == "focus" then
		if FocusFrame and FocusFrame.healthbar then
			return FocusFrame, FocusFrame.healthbar, FocusFrame.overAbsorbGlow
		end
		if
			FocusFrame
			and FocusFrame.TargetFrameContent
			and FocusFrame.TargetFrameContent.TargetFrameContentMain
			and FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBar
		then
			return FocusFrame, FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBar, FocusFrame.overAbsorbGlow
		end
	end

	return nil, nil, nil
end

local function UpdateBlizzardUnitFrame(unit)
	local unitFrame, healthBar, overAbsorbGlow = GetBlizzardUnitHealthBar(unit)

	if not unitFrame or not healthBar then
		return
	end

	local container = EnsureContainer(unitFrame, healthBar, overAbsorbGlow)

	Update(container, unit)
end

local function UpdateCompactFrame(frame)
	if not frame or frame:IsForbidden() or not frame.healthBar or not frame.unit then
		return
	end

	local unit = frame.unit

	local container = EnsureContainer(frame, frame.healthBar, frame.overAbsorbGlow)
	Update(container, unit)

	scheduler:RunWhenCombatEnds(function()
		if frame:IsForbidden() then
			return
		end

		ReanchorOverAbsorbGlow(container)
	end, frame:GetName())
end

local function HookCompactUnitFrames()
	if CompactUnitFrame_UpdateAll then
		hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
			UpdateCompactFrame(frame)
		end)
	end

	if CompactUnitFrame_UpdateHealPrediction then
		hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", function(frame)
			UpdateCompactFrame(frame)
		end)
	end
end

local function OnEvent()
	UpdateBlizzardUnitFrame("player")
	UpdateBlizzardUnitFrame("target")
	UpdateBlizzardUnitFrame("focus")
end

local function OnAddonLoaded()
	addon.Scheduler:Init()

	eventsFrame = CreateFrame("Frame")
	eventsFrame:RegisterEvent("PLAYER_LOGIN")
	eventsFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
	eventsFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
	eventsFrame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player", "target", "focus")
	eventsFrame:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "player", "target", "focus")

	-- wait for frames to be created
	eventsFrame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_LOGIN" then
			HookCompactUnitFrames()

			eventsFrame:UnregisterEvent("PLAYER_LOGIN")
			eventsFrame:SetScript("OnEvent", OnEvent)
		end
	end)
end

mini:WaitForAddonLoad(OnAddonLoaded)

---@class Container
---@field UnitFrame table
---@field HealthBar table
---@field Absorb table
---@field OverAbsorbGlow table
