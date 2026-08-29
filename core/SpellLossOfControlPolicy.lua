local IG = _G.InterruptGlow
if not IG or not IG.Cooldown then return end

local Cooldown = IG.Cooldown
local _G = _G
local C_Spell = _G.C_Spell
local pcall = pcall
local type = type

local stateCache = {}
local lastGeneration = -1

local function ReadLossOfControlState(info)
    -- C_Spell.GetSpellLossOfControlCooldownInfo is
    -- SecretWhenCooldownsRestricted. Never compare or index the returned object
    -- until its accessibility is known.
    if not IG.CanAccess(info) then return "restricted" end
    if info == nil then return "clear" end

    local isActive, activeKnown = IG:ReadMember(info, "isActive")
    local replaces, replacesKnown = IG:ReadMember(info, "shouldReplaceNormalCooldown")
    if not activeKnown or not replacesKnown then return "restricted" end
    if type(isActive) ~= "boolean" or type(replaces) ~= "boolean" then
        return "restricted"
    end
    if isActive or replaces then return "blocked" end
    return "clear"
end

local function ReadSpellLossOfControlState(spellID)
    local generation = Cooldown.generation or 0
    if generation < lastGeneration then
        IG:WipeMap(stateCache)
    end
    lastGeneration = generation

    local cached = stateCache[spellID]
    if cached and cached.generation == generation then return cached.state end

    local state = "restricted"
    local getter = C_Spell and C_Spell.GetSpellLossOfControlCooldownInfo
    if type(getter) == "function" then
        local ok, info = pcall(getter, spellID)
        if ok then state = ReadLossOfControlState(info) end
    end

    stateCache[spellID] = {
        generation = generation,
        state = state,
    }
    return state
end

local originalGetCachedReadiness = Cooldown.GetCachedReadiness
function Cooldown:GetCachedReadiness(sourceKind, sourceID, gcdOnlyHint)
    if sourceKind == "spell" and type(sourceID) == "number" then
        local state = ReadSpellLossOfControlState(sourceID)
        if state == "blocked" then
            return false, nil, false, false, false, false
        end
        if state == "restricted" then
            return nil, nil, true, true, false, true
        end
    end

    return originalGetCachedReadiness(self, sourceKind, sourceID, gcdOnlyHint)
end

function Cooldown:ClearSpellLossOfControlCache()
    IG:WipeMap(stateCache)
    lastGeneration = self.generation or 0
end

IG:RegisterModule("SpellLossOfControlPolicy", {
    usesCurrentCSpellAPI = true,
    api = "C_Spell.GetSpellLossOfControlCooldownInfo",
    inaccessibleInfoFailsClosed = true,
    missingAPIOnTargetBuildFailsClosed = true,
    legacyGlobalUsed = false,
})
