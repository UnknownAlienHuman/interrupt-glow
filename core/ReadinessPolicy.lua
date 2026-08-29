local IG = _G.InterruptGlow
if not IG or not IG.Cooldown then return end

local Cooldown = IG.Cooldown
local _G = _G
local GetPetActionInfo = _G.GetPetActionInfo
local type = type
local pcall = pcall

local originalRefreshAbility = Cooldown.RefreshAbility

local function GetPetActionSlotUsable(slot)
    if type(GetPetActionInfo) ~= "function" or type(slot) ~= "number" then
        return nil, true
    end

    local ok, _name, _texture, _isToken, _isActive, _autoCastAllowed,
        _autoCastEnabled, _spellID, isUsable = pcall(GetPetActionInfo, slot)
    if not ok or not IG.CanAccess(isUsable) then
        return nil, true
    end
    if isUsable == true then return true, false end
    if isUsable == false then return false, false end
    return nil, true
end

local function ApplyPetGate(ability)
    if ability.sourceKind ~= "pet" then return false end

    local usable, restricted = GetPetActionSlotUsable(ability.sourceID)
    if restricted then
        local changed = ability.ready ~= false
            or ability.restricted ~= true
            or ability.hardRestricted ~= true
            or ability.needsPoll ~= false

        ability.ready = false
        ability.restricted = true
        ability.hardRestricted = true
        ability.needsPoll = false
        return changed
    end

    if usable == false then
        local changed = ability.ready ~= false
            or ability.hardRestricted ~= false
            or ability.needsPoll ~= false

        ability.ready = false
        ability.hardRestricted = false
        ability.needsPoll = false
        return changed
    end

    return false
end

-- Resolve hard restrictions after the base cooldown/charge/LoC snapshot but do
-- not touch visuals here. Cooldown:RefreshAll performs one Glow:RefreshAll after
-- every active ability has passed all policy layers.
function Cooldown:RefreshAbility(ability)
    local changed = originalRefreshAbility(self, ability)
    changed = ApplyPetGate(ability) or changed

    if ability.hardRestricted == true and ability.needsPoll == true then
        ability.needsPoll = false
        changed = true
    end
    return changed
end

IG:RegisterModule("ReadinessPolicy", {
    hardRestrictionsCannotPoll = true,
    petUsabilityGate = true,
    batchedVisualCommit = true,
})
