local IG = _G.InterruptGlow
if not IG or not IG.Cooldown then return end

local Cooldown = IG.Cooldown
local _G = _G
local GetPetActionSlotUsable = _G.GetPetActionSlotUsable
local type = type
local pcall = pcall
local pairs = pairs
local next = next

-- PetActionBar uses GetPetActionSlotUsable separately from its checksRange and
-- inRange fields. Gate only intrinsic pet-action usability; do not turn target
-- range into a global target/focus decision.
local originalGetCachedReadiness = Cooldown.GetCachedReadiness
function Cooldown:GetCachedReadiness(sourceKind, sourceID, gcdOnlyHint)
    if sourceKind == "pet" and type(GetPetActionSlotUsable) == "function" then
        local ok, usable = pcall(GetPetActionSlotUsable, sourceID)
        if not ok or not IG.CanAccess(usable) then
            -- Pet usability is a hard safety gate. Optimistic cooldown mode must
            -- not make a dead, disabled or inaccessible pet action glow.
            return nil, nil, true, false, false, true
        end

        if usable == false or usable == 0 then
            return false, nil, false, false, false, false
        end
        if usable ~= true and usable ~= 1 then
            return nil, nil, true, false, false, true
        end
    end

    return originalGetCachedReadiness(self, sourceKind, sourceID, gcdOnlyHint)
end

local originalRefreshAbility = Cooldown.RefreshAbility
function Cooldown:RefreshAbility(ability)
    local changed = originalRefreshAbility(self, ability)

    -- Restricted Loss of Control and inaccessible pet usability are changed by
    -- explicit LoC/restriction/pet events. Polling them four times per second
    -- during every relevant cast adds CPU without producing new information.
    if ability and ability.hardRestricted == true and ability.needsPoll == true then
        ability.needsPoll = false
        changed = true
    end

    return changed
end

-- Keep cooldown evaluation and visual application inside the shared frame batch.
-- The base implementation called Glow:RefreshAll() directly and Shared.lua could
-- then execute the already-dirty visual phase a second time in the same frame.
function Cooldown:RefreshAll()
    self.generation = self.generation + 1
    if self.generation > 2147483000 then
        self.generation = 1
        IG:WipeMap(self.cache.action)
        IG:WipeMap(self.cache.spell)
        IG:WipeMap(self.cache.pet)
    end

    IG:BumpStat(next(self.gcdHints) ~= nil and "cooldown.spellEventPasses" or "cooldown.otherPasses")

    local changed = false
    for _, ability in pairs(IG.AbilityStates) do
        if ability.sourceKind ~= nil and next(ability.records) ~= nil then
            if self:RefreshAbility(ability) then changed = true end
            IG:BumpStat("cooldown.abilitiesEvaluated")
        end
    end

    self:ClearGCDHints()

    if changed then
        -- Shared.Flush processes this later in the same frame; no duplicate pass.
        IG:MarkVisualDirty()
    elseif IG.Glow then
        IG.Glow:UpdateRuntimeDriver()
    end
end
