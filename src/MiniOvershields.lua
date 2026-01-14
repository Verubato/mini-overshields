local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework
local containers = {}
local eventsFrame
local texturesRoot = "Interface\\AddOns\\" .. addonName .. "\\Textures\\"
local overlayTexturePath = texturesRoot .. "RaidFrameShieldOverlay.BLP"

local function GetOvershieldAmount(unit)
	if CreateUnitHealPredictionCalculator then
		-- there's currently no way to get the overshield amount using this new API
		-- so we'll just have to always show an overshield amount unfortunately
		local calculator = CreateUnitHealPredictionCalculator()
		calculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)

		UnitGetDetailedHealPrediction(unit, unit, calculator)

		local absorbsOverMaxHp, _ = calculator:GetDamageAbsorbs()
		return absorbsOverMaxHp, true
	else
		local unitHealth = UnitHealth(unit)
		local maxHealth = UnitHealthMax(unit) or 0
		local absorbs = UnitGetTotalAbsorbs(unit) or 0

		if mini:IsSecret(unitHealth) or mini:IsSecret(maxHealth) or mini:IsSecret(absorbs) then
			-- shouldn't happen, as this only happens in Midnight in which case we would have used the calculator
			return false
		end

		local missing = maxHealth - unitHealth
		local overshields = absorbs - missing

		return overshields, overshields > 0
	end
end

local function RaiseChildrenAboveAbsorb(unitFrame, absorbBar)
	if unitFrame:IsForbidden() then
		return
	end

	local buffs = unitFrame.buffFrames
	local debuffs = unitFrame.debuffFrames
	local baseLevel = absorbBar:GetFrameLevel()

	if type(buffs) == "table" then
		for _, frame in ipairs(buffs) do
			frame:SetFrameLevel(baseLevel + 1)
		end
	end

	if type(debuffs) == "table" then
		for _, frame in ipairs(debuffs) do
			frame:SetFrameLevel(baseLevel + 1)
		end
	end
end

local function EnsureContainer(healthBar)
	if containers[healthBar] then
		return containers[healthBar]
	end

	local container = {}
	local absorbBar = CreateFrame("StatusBar", nil, healthBar)
	absorbBar:SetAllPoints(healthBar)
	absorbBar:SetReverseFill(true)
	absorbBar:SetMinMaxValues(0, 1)
	-- make it invisible
	absorbBar:SetStatusBarTexture(0, 0, 0, 0)
	absorbBar:SetValue(0)
	-- show so our absorb texture also shows
	absorbBar:Show()

	local absorbTexture = absorbBar:GetStatusBarTexture()

	local overlay = absorbBar:CreateTexture(nil, "OVERLAY")
	overlay:SetPoint("TOPRIGHT", absorbTexture, "TOPRIGHT")
	overlay:SetPoint("BOTTOMLEFT", absorbTexture, "BOTTOMLEFT")

	-- enable repeat tiling so the pattern doesn't stretch
	overlay:SetTexture(overlayTexturePath, "REPEAT", "REPEAT")
	overlay:SetHorizTile(true)
	overlay:SetVertTile(true)

	container.Absorb = absorbBar
	container.Overlay = overlay
	containers[healthBar] = container

	return container
end

local function UpdateOverlayForUnit(healthBar, unit)
	if not UnitExists(unit) then
		return
	end

	local container = EnsureContainer(healthBar)

	if not container then
		return
	end

	local maxHealth = UnitHealthMax(unit) or 0
	local overshield, hasOvershield = GetOvershieldAmount(unit)

	container.Absorb:SetMinMaxValues(0, maxHealth)
	container.Absorb:SetValue(overshield)

	if mini:IsSecret(hasOvershield) then
		container.Absorb:SetAlphaFromBoolean(hasOvershield, 1, 0)
	else
		if hasOvershield then
			container.Absorb:Show()
		else
			container.Absorb:Hide()
		end
	end
end

local function GetBlizzardUnitHealthBar(unit)
	if unit == "player" then
		if PlayerFrame and PlayerFrame.healthbar then
			return PlayerFrame.healthbar
		end
		if
			PlayerFrame
			and PlayerFrame.PlayerFrameContent
			and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
			and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar
		then
			return PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBar
		end
	elseif unit == "target" then
		if TargetFrame and TargetFrame.healthbar then
			return TargetFrame.healthbar
		end
		if
			TargetFrame
			and TargetFrame.TargetFrameContent
			and TargetFrame.TargetFrameContent.TargetFrameContentMain
			and TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBar
		then
			return TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBar
		end
	elseif unit == "focus" then
		if FocusFrame and FocusFrame.healthbar then
			return FocusFrame.healthbar
		end
		if
			FocusFrame
			and FocusFrame.TargetFrameContent
			and FocusFrame.TargetFrameContent.TargetFrameContentMain
			and FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBar
		then
			return FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBar
		end
	end

	return nil
end

local function UpdateBlizzardUnitFrame(unit)
	local hb = GetBlizzardUnitHealthBar(unit)

	if hb then
		UpdateOverlayForUnit(hb, unit)
	end
end

local function UpdateCompactFrame(frame)
	if not frame or frame:IsForbidden() then
		return
	end

	local unit = frame.unit
	if not unit then
		return
	end

	local hb = frame.healthBar or frame.HealthBar

	if not hb then
		return
	end

	UpdateOverlayForUnit(hb, unit)
end

local function HookCompactAuras()
	if CompactUnitFrame_UpdateAuras then
		hooksecurefunc("CompactUnitFrame_UpdateAuras", function(frame)
			if not frame or frame:IsForbidden() then
				return
			end

			local hb = frame.healthBar or frame.HealthBar

			if not hb then
				return
			end

			local container = containers[hb] or EnsureContainer(hb)

			if container then
				RaiseChildrenAboveAbsorb(frame, container.Absorb)
			end
		end)
	end

	if CompactUnitFrame_UpdateAll then
		hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
			if not frame or frame:IsForbidden() then
				return
			end

			local hb = frame.healthBar or frame.HealthBar

			if not hb then
				return
			end

			local container = containers[hb] or EnsureContainer(hb)

			if container then
				RaiseChildrenAboveAbsorb(frame, container.Absorb)
			end
		end)
	end
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
			HookCompactAuras()

			eventsFrame:UnregisterEvent("PLAYER_LOGIN")
			eventsFrame:SetScript("OnEvent", OnEvent)
		end
	end)
end

mini:WaitForAddonLoad(OnAddonLoaded)
