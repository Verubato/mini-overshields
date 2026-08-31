local _, addon = ...
---@type MiniFramework
local mini = addon.Framework
---@type Container[]
local containers = {}
local eventsFrame
-- Whether the personal resource display cvar is on. Only CVAR_UPDATE changes it.
local prdEnabled
-- Whether a personal resource refresh is already waiting on the next frame.
local personalResourceQueued = false
-- Whether a unit token is a compound one, worked out once per token. The set of tokens is
-- small and fixed, and this is asked on the hottest hook in the game.
local compoundUnits = {}
local PRD_KEY = "PersonalResourceDisplay"

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
		ReanchorOverAbsorbGlow(container)
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

---Compound units (e.g. "raid1target", "boss1targetpet") carry a digit followed by a letter.
---A "pet" run right after the digit is the unit's own pet, not a nested token, so it stays simple.
local function IsCompoundUnit(unit)
	local known = compoundUnits[unit]

	if known == nil then
		known = unit:match("%d%a") ~= nil and unit:match("%d+pet$") == nil
		compoundUnits[unit] = known
	end

	return known
end

local function UpdateCompactFrame(frame)
	if not frame or mini:IsSecret(frame) or frame:IsForbidden() or not frame.healthBar or not frame.unit then
		return
	end

	local unit = frame.unit

	if IsCompoundUnit(unit) then
		return
	end

	local container = EnsureContainer(frame, frame.healthBar, frame.overAbsorbGlow)
	Update(container, unit)

	if container.OverAbsorbGlow then
		ReanchorOverAbsorbGlow(container)

		if frame.UpdateAnchors and not frame.MiniOvershieldsHooked then
			hooksecurefunc(frame, "UpdateAnchors", function()
				ReanchorOverAbsorbGlow(container)
			end)
			frame.MiniOvershieldsHooked = true
		end
	end
end

local function HookCompactUnitFrames()
	if CompactUnitFrame_UpdateAll then
		hooksecurefunc("CompactUnitFrame_UpdateAll", UpdateCompactFrame)
	end

	if CompactUnitFrame_UpdateHealPrediction then
		hooksecurefunc("CompactUnitFrame_UpdateHealPrediction", UpdateCompactFrame)
	end
end

---@return table? healthBar
---@return table? overAbsorbGlow
local function GetPersonalResourceHealthBar()
	-- The personal resource display is only active when this CVar is enabled. Read on demand
	-- and kept, because CVAR_UPDATE below is what changes the answer.
	if prdEnabled == nil then
		prdEnabled = GetCVar("nameplateShowSelf") == "1"
	end

	if not prdEnabled then
		return nil, nil
	end

	if
		PersonalResourceDisplayFrame
		and PersonalResourceDisplayFrame.HealthBarsContainer
		and PersonalResourceDisplayFrame.HealthBarsContainer.healthBar
	then
		local healthBar = PersonalResourceDisplayFrame.HealthBarsContainer.healthBar
		-- The PRD health bar uses the compact unit frame template and carries the
		-- same overAbsorbGlow field that compact party/raid frames do.
		return healthBar, healthBar.overAbsorbGlow
	end

	return nil, nil
end

local function UpdatePersonalResourceFrame()
	local healthBar, overAbsorbGlow = GetPersonalResourceHealthBar()

	if not healthBar then
		-- If the bar is gone or the CVar is off, remove any cached container so
		-- it is rebuilt cleanly next time the PRD is re-enabled.
		containers[PRD_KEY] = nil
		return
	end

	local container = containers[PRD_KEY]
	if not container then
		container = EnsureContainer(PRD_KEY, healthBar, overAbsorbGlow)
	end

	Update(container, "player")

	-- Keep the glow anchored to the left edge of our absorb texture, exactly
	-- as compact frames do. This must run every update because the absorb
	-- StatusBar texture resizes as the absorb value changes.
	if container.OverAbsorbGlow then
		ReanchorOverAbsorbGlow(container)
	end
end

local function OnPersonalResourceTick()
	personalResourceQueued = false
	UpdatePersonalResourceFrame()
end

---Refreshes the personal resource display a frame from now, once, however many events asked.
---Absorb events arrive in bursts while a shield is being cast onto a target.
local function QueuePersonalResourceUpdate()
	if personalResourceQueued then
		return
	end

	personalResourceQueued = true
	-- Deferred so Blizzard's own update has run and the glow visibility is accurate.
	C_Timer.After(0, OnPersonalResourceTick)
end

local function OnEvent(_, event, cvarName)
	if event == "CVAR_UPDATE" then
		-- React to the player toggling the personal resource display on or off.
		if cvarName == "nameplateShowSelf" then
			prdEnabled = nil
			UpdatePersonalResourceFrame()
		end
		return
	end

	-- /console and ConsoleExec can move the cvar without a CVAR_UPDATE, so re-read it on a
	-- world change rather than trusting the cache for the rest of the session.
	if event == "PLAYER_ENTERING_WORLD" then
		prdEnabled = nil
	end

	UpdateBlizzardUnitFrame("player")
	UpdateBlizzardUnitFrame("target")
	UpdateBlizzardUnitFrame("focus")
	QueuePersonalResourceUpdate()
end

local function OnAddonLoaded()
	eventsFrame = CreateFrame("Frame")
	eventsFrame:RegisterEvent("PLAYER_LOGIN")
	eventsFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
	eventsFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
	eventsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventsFrame:RegisterEvent("CVAR_UPDATE")
	eventsFrame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player", "target", "focus")
	eventsFrame:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "player", "target", "focus")

	-- wait for frames to be created
	eventsFrame:SetScript("OnEvent", function(_, event, ...)
		if event == "PLAYER_LOGIN" then
			HookCompactUnitFrames()
			UpdatePersonalResourceFrame()

			eventsFrame:UnregisterEvent("PLAYER_LOGIN")
			eventsFrame:SetScript("OnEvent", OnEvent)
		end
	end)
end

mini:WaitForAddonLoad(OnAddonLoaded)

---@class Container
---@field UnitFrame table|string  -- string sentinel "PersonalResourceDisplay" is used for the PRD health bar
---@field HealthBar table
---@field Absorb table
---@field OverAbsorbGlow table?
