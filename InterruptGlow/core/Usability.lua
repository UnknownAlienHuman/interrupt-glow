local IG = _G.InterruptGlow
if not IG or not IG.Cooldown then return end

local Usability = {}
IG.Usability = Usability
IG:RegisterModule("Usability", Usability)

local Cooldown = IG.Cooldown
local _G = _G
local C_ActionBar = _G.C_ActionBar
local C_Spell = _G.C_Spell
local type = type
local pcall = pcall
local pairs = pairs
local next = next

local function ReadUsable(fn, sourceID)
    if type(fn) ~= "function" or type(sourceID) ~= "number" then
        return nil, true
    end

    local ok, usable = pcall(fn, sourceID)
    if not ok or not IG.CanAccess(usable) then
        return nil, true
    end
    if usable == true then return true, false end
    if usable == false then return false, false end
    return nil, true
end

-- Wrap the already-normalized cooldown/charge/LoC/pet policy. Known unusable is
-- an exact not-ready result; inaccessible usability is a hard fail-closed gate
-- that optimistic cooldown compatibility cannot override.
local originalGetCachedReadiness = Cooldown.GetCachedReadiness
function Cooldown:GetCachedReadiness(sourceKind, sourceID, gcdOnlyHint)
    if sourceKind == "action" then
        local usable, restricted = ReadUsable(
            C_ActionBar and C_ActionBar.IsUsableAction,
            sourceID
        )
        if restricted then return nil, nil, true, false, false, true end
        if usable == false then return false, nil, false, false, false, false end
    elseif sourceKind == "spell" then
        local usable, restricted = ReadUsable(
            C_Spell and C_Spell.IsSpellUsable,
            sourceID
        )
        if restricted then return nil, nil, true, false, false, true end
        if usable == false then return false, nil, false, false, false, false end
    end

    return originalGetCachedReadiness(self, sourceKind, sourceID, gcdOnlyHint)
end

function Usability:IsTrackedActionSlot(slot)
    if type(slot) ~= "number" then return false end
    for _, ability in pairs(IG.AbilityStates) do
        if ability.sourceKind == "action"
            and ability.sourceID == slot
            and next(ability.records) ~= nil
        then
            return true
        end
    end
    return false
end

function Usability:HasTrackedSpellSource()
    for _, ability in pairs(IG.AbilityStates) do
        if ability.sourceKind == "spell" and next(ability.records) ~= nil then
            return true
        end
    end
    return false
end

function Usability:OnActionUsableChanged(changes)
    if not IG.CanAccess(changes) or type(changes) ~= "table" then
        -- Payload unexpectedly inaccessible: one bounded refresh is safer than
        -- treating the previous usability state as authoritative.
        IG:MarkCooldownDirty(false)
        return
    end

    for index = 1, #changes do
        local change = changes[index]
        if not IG.CanAccess(change) then
            IG:MarkCooldownDirty(false)
            return
        end

        local slot, slotKnown = IG:ReadMember(change, "slot")
        if not slotKnown or type(slot) ~= "number" then
            IG:MarkCooldownDirty(false)
            return
        end

        if self:IsTrackedActionSlot(slot) then
            IG:BumpStat("events.actionUsableChanged")
            IG:MarkCooldownDirty(false)
            return
        end
    end
end
