local IG = _G.InterruptGlow
if not IG then return end

local Resolver = {}
IG.ActionResolver = Resolver

local C_ActionBar = _G.C_ActionBar
local GetActionInfo = _G.GetActionInfo
local type = type
local pcall = pcall
local SPELL_METHODS = { "GetSpellId", "GetSpellID" }

local function ReadObjectMember(object, key)
    if type(IG.ReadObjectMember) == "function" then
        return IG:ReadObjectMember(object, key)
    end
    return IG:ReadMember(object, key)
end

local function PositiveSlot(value)
    local slot = IG:AsNumber(value)
    if type(slot) == "number" and slot > 0 and slot % 1 == 0 then return slot end
    return nil
end

function Resolver:GetActionSlot(button)
    local stateType, stateTypeKnown = ReadObjectMember(button, "_state_type")
    if stateTypeKnown and stateType == "action" then
        local stateAction, stateActionKnown = ReadObjectMember(button, "_state_action")
        if stateActionKnown then
            local slot = PositiveSlot(stateAction)
            if slot then return slot end
        end
    end
    local action, actionKnown = ReadObjectMember(button, "action")
    if actionKnown then return PositiveSlot(action) end
    return nil
end

local function ReadBooleanAPI(fn, slot, native)
    if type(fn) ~= "function" then return nil end
    local value
    if native then
        value = fn(slot)
    else
        local ok
        ok, value = pcall(fn, slot)
        if not ok then return nil end
    end
    if not IG.CanAccess(value) then return nil end
    if value == true then return true end
    if value == false then return false end
    return nil
end

local function ReadActionInfo(slot, native)
    if type(GetActionInfo) ~= "function" then return nil, nil, nil end
    local actionType, id, subType
    if native then
        actionType, id, subType = GetActionInfo(slot)
    else
        local ok
        ok, actionType, id, subType = pcall(GetActionInfo, slot)
        if not ok then return nil, nil, nil end
    end
    if not IG.CanAccess(actionType) or not IG.CanAccess(id) or not IG.CanAccess(subType) then
        return nil, nil, nil
    end
    return actionType, id, subType
end

local function ReadSpellID(slot, native, actionType, id, subType)
    local getSpell = C_ActionBar and C_ActionBar.GetSpell
    if type(getSpell) == "function" then
        local spellID
        if native then
            spellID = getSpell(slot)
        else
            local ok
            ok, spellID = pcall(getSpell, slot)
            if not ok then spellID = nil end
        end
        if IG.CanAccess(spellID) and type(spellID) == "number" then return spellID end
    end
    if actionType == "spell" and type(id) == "number" then return id end
    if actionType == "macro" and subType == "spell" and type(id) == "number" then return id end
    return nil
end

local function ReadDirectSpellID(button)
    for index = 1, #SPELL_METHODS do
        local methodName = SPELL_METHODS[index]
        local method, readable = ReadObjectMember(button, methodName)
        if readable and type(method) == "function" then
            local ok, value = pcall(method, button)
            if ok and IG.CanAccess(value) and type(value) == "number" then return value end
            return nil
        end
    end
    local stateType, typeKnown = ReadObjectMember(button, "_state_type")
    if typeKnown and stateType == "spell" then
        local value, known = ReadObjectMember(button, "_state_action")
        if known then return PositiveSlot(value) end
    end
    return nil
end

function Resolver:ResolveRecord(record)
    if not record then return false end
    local Buttons = IG.Buttons
    if record.adapter == "pet" then return Buttons:ResolvePet(record) end
    if record.adapter == "cdm" then return Buttons:ResolveCDM(record) end
    if record.adapter == "buttonforge" then return Buttons:ResolveButtonForge(record) end

    local slot
    if record.adapter == "lab" then
        -- LABAdapter snapshots secure identity after UpdateAction. Treat that
        -- snapshot as authoritative: `button.action` can survive a state switch
        -- and must not resurrect a prior physical action when LAB reports an
        -- empty, restricted, or non-action state.
        local stateType = record.labStateType
        local stateAction = record.labStateAction
        if record.labIdentityRestricted == true
            or not IG.CanAccess(stateType)
            or not IG.CanAccess(stateAction)
        then
            return false
        end

        if stateType == "spell" then
            local spellID = PositiveSlot(stateAction)
            if not spellID then return false end
            local canonical = IG.Data:GetCanonicalSpellID(spellID, "spell")
            if canonical then return true, "spell", canonical, spellID, canonical end
            return false
        end

        if stateType ~= "action" then return false end
        slot = PositiveSlot(record.labSlot)
        if not slot then return false end
    elseif record.adapter == "dominos" then
        -- The Dominos controller owns the current secure action mapping. Do not
        -- create a second identity path from the button's generic action field.
        slot = PositiveSlot(record.dominosSlot)
        if not slot then return false end
    else
        slot = self:GetActionSlot(record.button)
    end

    if not slot then
        local spellID = ReadDirectSpellID(record.button)
        local canonical = spellID and IG.Data:GetCanonicalSpellID(spellID, "spell")
        if canonical then return true, "spell", canonical, spellID, canonical end
        return false
    end

    local native = record.adapter == "native"
    local interrupt = ReadBooleanAPI(C_ActionBar and C_ActionBar.IsInterruptAction, slot, native)
    -- Most changing buttons are not interrupts. Stop after one classification
    -- query; callbacks never resolve actions and the dirty queue coalesces them.
    if interrupt == false then return false end
    local assisted = ReadBooleanAPI(C_ActionBar and C_ActionBar.IsAssistedCombatAction, slot, native)
    if assisted == true then return false end

    local actionType, id, subType = ReadActionInfo(slot, native)
    if subType == "assistedcombat" then return false end
    local spellID = ReadSpellID(slot, native, actionType, id, subType)
    local canonical = spellID and IG.Data:GetCanonicalSpellID(spellID, "action")
    if interrupt == true then
        if spellID and not canonical then canonical = IG.Data:LearnRuntimeInterrupt(spellID) end
        return true, "action", slot, spellID, canonical or spellID
    end
    if canonical then return true, "action", slot, spellID, canonical end
    return false
end
