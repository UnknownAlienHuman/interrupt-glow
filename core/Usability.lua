local IG = _G.InterruptGlow
if not IG or not IG.Cooldown then return end

local Cooldown = IG.Cooldown
local _G = _G
local C_ActionBar = _G.C_ActionBar
local C_Spell = _G.C_Spell
local type = type
local pcall = pcall
local pairs = pairs

local function NormalizeUsability(ok, usable, noMana)
    if not ok or not IG.CanAccess(usable) or not IG.CanAccess(noMana) then
        return nil, nil, true
    end
    if type(usable) ~= "boolean" or type(noMana) ~= "boolean" then
        return nil, nil, true
    end
    return usable, noMana, false
end

local function ReadActionUsability(slot)
    if not C_ActionBar or type(C_ActionBar.IsUsableAction) ~= "function" then
        return nil, nil, true
    end
    return NormalizeUsability(pcall(C_ActionBar.IsUsableAction, slot))
end

local function ReadSpellUsability(spellID)
    if not C_Spell or type(C_Spell.IsSpellUsable) ~= "function" then
        return nil, nil, true
    end
    return NormalizeUsability(pcall(C_Spell.IsSpellUsable, spellID))
end

local function ReadActionOrSpellUsability(ability)
    if ability.sourceKind == "action" then
        return ReadActionUsability(ability.sourceID)
    end
    if ability.sourceKind == "spell" then
        return ReadSpellUsability(ability.sourceID)
    end
    return true, false, false
end

local function ApplyUsabilityGate(ability)
    local usable, noMana, hardRestricted = ReadActionOrSpellUsability(ability)
    local changed = false

    if hardRestricted then
        changed = ability.ready ~= false
            or ability.restricted ~= true
            or ability.hardRestricted ~= true
            or ability.needsPoll ~= false
        ability.ready = false
        ability.restricted = true
        ability.hardRestricted = true
        ability.needsPoll = false
    elseif usable == false or noMana == true then
        changed = ability.ready ~= false or ability.needsPoll ~= false
        ability.ready = false
        ability.needsPoll = false
    end
    return changed
end

local originalRefreshAbility = Cooldown.RefreshAbility
function Cooldown:RefreshAbility(ability)
    local changed = originalRefreshAbility(self, ability)
    changed = ApplyUsabilityGate(ability) or changed
    return changed
end

local Usability = {}
IG.Usability = Usability
IG:RegisterModule("Usability", Usability)

function Usability:HasTrackedSpellSource()
    for _, ability in pairs(IG.AbilityStates) do
        if ability.sourceKind == "spell" and next(ability.records) ~= nil then
            return true
        end
    end
    return false
end

function Usability:OnActionUsableChanged(changes)
    if not IG.CanAccess(changes) or type(changes) ~= "table" then return false end

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

Usability.batchedVisualCommit = true
