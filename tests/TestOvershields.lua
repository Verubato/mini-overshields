-- Drives EnsureContainer, Update and IsCompoundUnit entirely through the CompactUnitFrame_UpdateAll
-- hook, the same way Blizzard's raid frame code calls into this addon.
--
-- The mock's issecretvalue always answers false (see build/Lua/WowMock.lua), so the secret
-- guard below swaps it out for one that recognises a chosen sentinel as the only secret
-- value, exactly where a real secret strata would arrive.

local fw = require("TestFramework")
local harness = require("AddonHarness")
local WowMock = require("WowMock")

---Overrides one or more globals for the duration of fn, restoring them even if fn raises,
---so one failing assertion can't leave a later test running against a patched global.
---@param overrides table<string, any>
---@param fn fun()
local function WithGlobals(overrides, fn)
	local reals = {}

	for name, value in pairs(overrides) do
		reals[name] = _G[name]
		_G[name] = value
	end

	local ok, err = pcall(fn)

	for name, value in pairs(reals) do
		_G[name] = value
	end

	if not ok then
		error(err, 0)
	end
end

local function NewCompactFrame(unit, withGlow)
	local frame = WowMock.NewFrame("Frame")
	frame.unit = unit
	frame.healthBar = WowMock.NewFrame("Frame")

	if withGlow then
		frame.overAbsorbGlow = WowMock.NewFrame("Frame")
	end

	return frame
end

local function FindAbsorbBar(healthBar)
	for _, frame in ipairs(WowMock.Frames) do
		if frame.__objectType == "StatusBar" and frame.__parent == healthBar then
			return frame
		end
	end
end

fw.describe("MiniOvershields - IsCompoundUnit", function()
	fw.before_each(function()
		harness.Run("MiniOvershields")
	end)

	local cases = {
		{ unit = "player", compound = false },
		{ unit = "raid1", compound = false },
		{ unit = "raid1target", compound = true },
		{ unit = "boss1targetpet", compound = true },
		-- Not literally nested, but the pattern is a bare digit-then-letter run, so this
		-- matches the same as the deliberately compound cases above. Pinning today's answer.
		{ unit = "raid1pet", compound = true },
	}

	for _, case in ipairs(cases) do
		fw.it('treats "' .. case.unit .. '" as ' .. (case.compound and "compound" or "simple"), function()
			local frame = NewCompactFrame(case.unit)

			_G.CompactUnitFrame_UpdateAll(frame)

			local absorb = FindAbsorbBar(frame.healthBar)

			if case.compound then
				fw.is_nil(absorb, "compound units are skipped before EnsureContainer ever runs")
			else
				fw.not_nil(absorb, "simple units get an absorb bar built")
			end
		end)
	end
end)

fw.describe("MiniOvershields - Update", function()
	fw.before_each(function()
		harness.Run("MiniOvershields")
	end)

	fw.it("sets the absorb bar's range to max health and its value to the current absorb", function()
		local frame = NewCompactFrame("party1")

		_G.UnitHealthMax = function()
			return 200
		end
		_G.UnitGetTotalAbsorbs = function()
			return 50
		end

		_G.CompactUnitFrame_UpdateAll(frame)

		local absorb = FindAbsorbBar(frame.healthBar)
		local min, max = absorb:GetMinMaxValues()

		fw.eq(min, 0, "min stays 0")
		fw.eq(max, 200, "max tracks UnitHealthMax")
		fw.eq(absorb:GetValue(), 50, "value tracks UnitGetTotalAbsorbs")
	end)

	fw.it("still sets a value above max when the absorb overshields", function()
		local frame = NewCompactFrame("party1")

		_G.UnitHealthMax = function()
			return 100
		end
		_G.UnitGetTotalAbsorbs = function()
			return 150
		end

		_G.CompactUnitFrame_UpdateAll(frame)

		local absorb = FindAbsorbBar(frame.healthBar)
		local _, max = absorb:GetMinMaxValues()

		fw.eq(max, 100, "range still comes from max health")
		fw.eq(absorb:GetValue(), 150, "value is left over max, uncapped")
	end)

	fw.it("sets a value of 0 with no absorb up", function()
		local frame = NewCompactFrame("party1")

		_G.UnitHealthMax = function()
			return 100
		end
		_G.UnitGetTotalAbsorbs = function()
			return 0
		end

		_G.CompactUnitFrame_UpdateAll(frame)

		local absorb = FindAbsorbBar(frame.healthBar)

		fw.eq(absorb:GetValue(), 0, "no absorb, no value")
	end)
end)

fw.describe("MiniOvershields - glow visibility", function()
	fw.before_each(function()
		harness.Run("MiniOvershields")
	end)

	fw.it("shows the absorb bar once the overabsorb glow is visible", function()
		local frame = NewCompactFrame("party1", true)
		frame.overAbsorbGlow:Show()

		_G.CompactUnitFrame_UpdateAll(frame)

		local absorb = FindAbsorbBar(frame.healthBar)

		fw.truthy(absorb:IsShown(), "glow visible means an overshield, so the bar shows")
	end)

	fw.it("hides the absorb bar once the overabsorb glow is hidden", function()
		local frame = NewCompactFrame("party1", true)
		frame.overAbsorbGlow:Show()

		_G.CompactUnitFrame_UpdateAll(frame)

		local absorb = FindAbsorbBar(frame.healthBar)
		fw.truthy(absorb:IsShown(), "shown first")

		frame.overAbsorbGlow:Hide()
		_G.CompactUnitFrame_UpdateAll(frame)

		fw.falsy(absorb:IsShown(), "hidden once the glow goes away")
	end)

	fw.it("always shows the absorb bar when the frame carries no overabsorb glow at all", function()
		local frame = NewCompactFrame("party1", false)

		_G.CompactUnitFrame_UpdateAll(frame)

		local absorb = FindAbsorbBar(frame.healthBar)

		fw.truthy(absorb:IsShown(), "no glow to check, so Update shows it unconditionally")
	end)
end)

fw.describe("MiniOvershields - container caching", function()
	fw.before_each(function()
		harness.Run("MiniOvershields")
	end)

	fw.it("builds only one absorb bar across repeated updates of the same frame", function()
		local frame = NewCompactFrame("party1")

		_G.CompactUnitFrame_UpdateAll(frame)
		_G.CompactUnitFrame_UpdateAll(frame)
		_G.CompactUnitFrame_UpdateAll(frame)

		local count = 0

		for _, candidate in ipairs(WowMock.Frames) do
			if candidate.__objectType == "StatusBar" and candidate.__parent == frame.healthBar then
				count = count + 1
			end
		end

		fw.eq(count, 1, "EnsureContainer returned the cached container on every later call")
	end)
end)

fw.describe("MiniOvershields - secret strata guard", function()
	fw.it("falls back to LOW when the health bar's strata is secret", function()
		harness.Run("MiniOvershields")

		local sentinel = {}
		local frame = NewCompactFrame("party1")
		frame.healthBar.GetFrameStrata = function()
			return sentinel
		end

		WithGlobals({
			issecretvalue = function(v)
				return v == sentinel
			end,
		}, function()
			fw.no_error(function()
				_G.CompactUnitFrame_UpdateAll(frame)
			end, "a secret strata read off the health bar")
		end)

		local absorb = FindAbsorbBar(frame.healthBar)

		fw.eq(absorb:GetFrameStrata(), "LOW", "guarded fallback used instead of the secret value")
	end)

	fw.it("keeps the health bar's own strata when it is not secret", function()
		harness.Run("MiniOvershields")

		local frame = NewCompactFrame("party1")
		frame.healthBar:SetFrameStrata("HIGH")

		_G.CompactUnitFrame_UpdateAll(frame)

		local absorb = FindAbsorbBar(frame.healthBar)

		fw.eq(absorb:GetFrameStrata(), "HIGH", "not secret, so the health bar's own strata carries through")
	end)
end)
