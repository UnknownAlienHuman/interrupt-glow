local IG = _G.InterruptGlow
if not IG or not IG.Buttons then return end

local Buttons = IG.Buttons
local _G = _G
local C_ActionBar = _G.C_ActionBar
local GetActionInfo = _G.GetActionInfo
local type = type
local pcall = pcall

local originalResolveRecord = Buttons.ResolveRecord

local function ResolveSlot(button)
    local stateType, stateTypeKnown = IG:ReadMember(button, "_state_type")
    if stateTypeKnown and stateType == "action" then
        local stateAction, stateActionKnown = IG:ReadMember(button, "_state_action")
        if stateActionKnown then
            local slot = IG:AsNumber(stateAction)
            if slot then return slot end
        end
    end

    local action, actionKnown = IG:ReadMember(button, "action")
    if actionKnown then return IG:AsNumber(action) end
    return nil
end

local function ReadActionSnapshot(slot)
    local actionType, id, subType
    if type(GetActionInfo) == "function" and type(slot) == "number" then
        local ok
        ok, actionType, id, subType = pcall(GetActionInfo, slot)
        if not ok
            or not IG.CanAccess(actionType)
            or not IG.CanAccess(id)
            or not IG.CanAccess(subType)
        then
            actionType, id, subType = nil, nil, nil
        end
    end

    local assisted = nil
    if C_ActionBar and type(C_ActionBar.IsAssistedCombatAction) == "function" then
        local ok, value = pcall(C_ActionBar.IsAssistedCombatAction, slot)
        if ok and IG.CanAccess(value) then assisted = value == true end
    end
    if assisted == nil then assisted = subType == "assistedcombat" end

    local interrupt = nil
    if C_ActionBar and type(C_ActionBar.IsInterruptAction) == "function" then
        local ok, value = pcall(C_ActionBar.IsInterruptAction, slot)
        if ok and IG.CanAccess(value) then
            if value == true then interrupt = true
            elseif value == false then interrupt = false end
        end
    end

    return actionType, id, subType, interrupt, assisted
end

local function StoreSnapshot(record, slot, actionType, id, subType, interrupt, assisted)
    local changed = record.actionSnapshotSlot ~= slot
        or record.actionSnapshotType ~= actionType
        or record.actionSnapshotID ~= id
        or record.actionSnapshotSubType ~= subType
        or record.actionSnapshotInterrupt ~= interrupt
        or record.actionSnapshotAssisted ~= assisted

    record.actionSnapshotSlot = slot
    record.actionSnapshotType = actionType
    record.actionSnapshotID = id
    record.actionSnapshotSubType = subType
    record.actionSnapshotInterrupt = interrupt
    record.actionSnapshotAssisted = assisted
    return changed
end

local function ResolveSnapshot(record, slot, actionType, id, subType, interrupt, assisted)
    if assisted == true then return false end

    if interrupt == true then
        local spellID = nil
        if actionType == "spell" and type(id) == "number" then
            spellID = id
        elseif actionType == "macro" and subType == "spell" and type(id) == "number" then
            spellID = id
        end

        local canonicalSpellID = spellID and IG.Data:GetCanonicalSpellID(spellID, "action") or nil
        if spellID and not canonicalSpellID then
            canonicalSpellID = IG.Data:LearnRuntimeInterrupt(spellID)
        end
        canonicalSpellID = canonicalSpellID or spellID
        return true, "action", slot, spellID, canonicalSpellID
    end

    if interrupt == false then return false end

    -- If the current build/provider does not expose a readable interrupt flag,
    -- retain the original direct-spell fallback and fail closed otherwise.
    return originalResolveRecord(Buttons, record)
end

function Buttons:ResolveRecord(record)
    if not record then return false end

    if record.adapter == "pet"
        or record.adapter == "cdm"
        or record.adapter == "buttonforge"
    then
        return originalResolveRecord(self, record)
    end

    local slot = ResolveSlot(record.button)
    if not slot then return originalResolveRecord(self, record) end

    local actionType, id, subType, interrupt, assisted = ReadActionSnapshot(slot)
    StoreSnapshot(record, slot, actionType, id, subType, interrupt, assisted)
    return ResolveSnapshot(record, slot, actionType, id, subType, interrupt, assisted)
end

function Buttons:OnNativeActionChanged(button)
    local record = self:ObserveButton(button, "native", { skipDirty = true })
    if not record then return end

    local slot = ResolveSlot(button)
    if not slot then
        IG:MarkButtonDirty(button)
        return
    end

    local actionType, id, subType, interrupt, assisted = ReadActionSnapshot(slot)
    if StoreSnapshot(record, slot, actionType, id, subType, interrupt, assisted) then
        IG:MarkButtonDirty(button)
        IG:BumpStat("events.nativeActionIdentityChanged")
    else
        IG:BumpStat("events.nativeActionIdentityUnchanged")
    end
end
