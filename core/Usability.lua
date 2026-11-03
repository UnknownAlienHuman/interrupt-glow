local IG = _G.InterruptGlow
if not IG or not IG.Cooldown then return end

local type = type
local pairs = pairs
local _G = _G
local C_ActionBar = _G.C_ActionBar
local C_Spell = _G.C_Spell
local pcall = pcall

local Usability = {}
IG.Usability = Usability
IG:RegisterModule("Usability", Usability)

local function ReadUsability(ok, usable, noMana, requiresNoMana)
    if not ok or not IG.CanAccess(usable) then return nil, nil, true end
    if type(usable) ~= "boolean" then return nil, nil, true end
    if requiresNoMana then
        if not IG.CanAccess(noMana) or type(noMana) ~= "boolean" then
            return nil, nil, true
        end
        return usable, noMana, false
    end
    return usable, false, false
end

function Usability:ReadForAbility(ability)
    local kind, sourceID = ability and ability.sourceKind, ability and ability.sourceID
    if kind == "action" then
        if not C_ActionBar or type(C_ActionBar.IsUsableAction) ~= "function" then
            return nil, nil, true
        end
        local ok, usable, noMana = pcall(C_ActionBar.IsUsableAction, sourceID)
        return ReadUsability(ok, usable, noMana, true)
    end
    if kind == "spell" then
        if not C_Spell or type(C_Spell.IsSpellUsable) ~= "function" then
            return nil, nil, true
        end
        local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, sourceID)
        return ReadUsability(ok, usable, noMana, true)
    end
    if kind == "pet" then
        if type(_G.GetPetActionSlotUsable) ~= "function" then return nil, nil, true end
        local ok, usable = pcall(_G.GetPetActionSlotUsable, sourceID)
        return ReadUsability(ok, usable, nil, false)
    end
    return nil, nil, true
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
    if IG.ConditionalActions then IG.ConditionalActions:OnUsabilityChanged(changes) end
    if not IG:NeedsReadinessRuntime() then return false end
    if not IG.CanAccessTable(changes) then
        IG:MarkCooldownDirty(false)
        return true
    end

    local matched = false
    for _, change in pairs(changes) do
        local slot, slotKnown = IG:ReadMember(change, "slot")
        if slotKnown then slot = IG:AsNumber(slot) end
        if type(slot) == "number" then
            for _, ability in pairs(IG.AbilityStates) do
                if ability.sourceKind == "action"
                    and ability.sourceID == slot
                    and next(ability.records) ~= nil
                then
                    matched = true
                    break
                end
            end
        end
        if matched then break end
    end

    if matched then IG:MarkCooldownDirty(false) end
    return matched
end

Usability.eventInvalidationOnly = true
