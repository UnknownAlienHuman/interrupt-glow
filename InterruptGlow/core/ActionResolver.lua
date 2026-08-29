local IG = _G.InterruptGlow
if not IG or not IG.Buttons then return end

local Buttons = IG.Buttons
local _G = _G
local C_ActionBar = _G.C_ActionBar
local GetActionInfo = _G.GetActionInfo
local type = type
local pcall = pcall

local originalResolveRecord = Buttons.ResolveRecord

local function TrackHotPath(key)
    if IG.DB.debug == true or IG.profileCountersEnabled == true then
        IG:BumpStat(key)
    end
end

local function PositiveSlot(value)
    local slot = IG:AsNumber(value)
    if type(slot) == "number" and slot > 0 then return slot end
    return nil
end

local function ResolveNativeSlot(button)
    if not button then return nil end
    local action = button.action
    if not IG.CanAccess(action) then return nil end
    return PositiveSlot(action)
end

local function ResolveSlot(button)
    local stateType, stateTypeKnown = IG:ReadMember(button, "_state_type")
    if stateTypeKnown and stateType == "action" then
        local stateAction, stateActionKnown = IG:ReadMember(button, "_state_action")
        if stateActionKnown then
            local slot = PositiveSlot(stateAction)
            if slot then return slot end
        end
    end

    local action, actionKnown = IG:ReadMember(button, "action")
    if actionKnown then return PositiveSlot(action) end
    return nil
end

local function ReadBooleanAPI(fn, slot, trustedSlot)
    if type(fn) ~= "function" then return nil end

    local value
    if trustedSlot then
        -- Native Blizzard action buttons expose a valid positive action slot.
        -- Avoid a protected-call frame in the dominant mouseover feedback path.
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

local function ReadActionInfo(slot, trustedSlot)
    if type(GetActionInfo) ~= "function" then return nil, nil, nil end

    local actionType, id, subType
    if trustedSlot then
        actionType, id, subType = GetActionInfo(slot)
    else
        local ok
        ok, actionType, id, subType = pcall(GetActionInfo, slot)
        if not ok then return nil, nil, nil end
    end

    if not IG.CanAccess(actionType)
        or not IG.CanAccess(id)
        or not IG.CanAccess(subType)
    then
        return nil, nil, nil
    end
    return actionType, id, subType
end

local function ReadResolvedSpellID(slot, trustedSlot, actionType, id, subType)
    local getSpell = C_ActionBar and C_ActionBar.GetSpell
    if type(getSpell) == "function" then
        local spellID
        if trustedSlot then
            spellID = getSpell(slot)
        else
            local ok
            ok, spellID = pcall(getSpell, slot)
            if not ok then spellID = nil end
        end

        if IG.CanAccess(spellID) and type(spellID) == "number" then
            return spellID
        end
    end

    if actionType == "spell" and type(id) == "number" then return id end
    if actionType == "macro" and subType == "spell" and type(id) == "number" then return id end
    return nil
end

local function ReadActionSnapshot(slot, trustedSlot)
    local isInterrupt = C_ActionBar and C_ActionBar.IsInterruptAction
    local interrupt = ReadBooleanAPI(isInterrupt, slot, trustedSlot)

    -- Dominant mouseover path: one current-action classification call and no
    -- GetActionInfo, GetSpell, assisted-combat query, cooldown work or allocation.
    if interrupt == false then
        return nil, nil, nil, nil, false, nil
    end

    local isAssisted = C_ActionBar and C_ActionBar.IsAssistedCombatAction
    local assisted = nil
    if interrupt == true then
        assisted = ReadBooleanAPI(isAssisted, slot, trustedSlot)
        if assisted == true then
            return nil, nil, nil, nil, true, true
        end
    end

    local actionType, id, subType = ReadActionInfo(slot, trustedSlot)
    if subType == "assistedcombat" then
        assisted = true
    elseif assisted == nil and interrupt == nil then
        assisted = ReadBooleanAPI(isAssisted, slot, trustedSlot)
    end

    local spellID = ReadResolvedSpellID(slot, trustedSlot, actionType, id, subType)
    return actionType, id, subType, spellID, interrupt, assisted
end

local function StoreSnapshot(record, slot, actionType, id, subType, spellID, interrupt, assisted)
    local changed = record.actionSnapshotSlot ~= slot
        or record.actionSnapshotType ~= actionType
        or record.actionSnapshotID ~= id
        or record.actionSnapshotSubType ~= subType
        or record.actionSnapshotSpellID ~= spellID
        or record.actionSnapshotInterrupt ~= interrupt
        or record.actionSnapshotAssisted ~= assisted

    record.actionSnapshotSlot = slot
    record.actionSnapshotType = actionType
    record.actionSnapshotID = id
    record.actionSnapshotSubType = subType
    record.actionSnapshotSpellID = spellID
    record.actionSnapshotInterrupt = interrupt
    record.actionSnapshotAssisted = assisted
    return changed
end

local function ResolveSnapshot(record, slot, spellID, interrupt, assisted)
    if interrupt == false or assisted == true then return false end

    if interrupt == true then
        local canonicalSpellID = spellID and IG.Data:GetCanonicalSpellID(spellID, "action") or nil
        if spellID and not canonicalSpellID then
            canonicalSpellID = IG.Data:LearnRuntimeInterrupt(spellID)
        end
        canonicalSpellID = canonicalSpellID or spellID
        return true, "action", slot, spellID, canonicalSpellID
    end

    if spellID then
        local canonicalSpellID = IG.Data:GetCanonicalSpellID(spellID, "action")
        if canonicalSpellID then
            return true, "action", slot, spellID, canonicalSpellID
        end
        return false
    end

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

    local trustedSlot = record.adapter == "native"
    local slot = trustedSlot and ResolveNativeSlot(record.button) or ResolveSlot(record.button)
    if not slot then
        if trustedSlot then return false end
        return originalResolveRecord(self, record)
    end

    local actionType, id, subType, spellID, interrupt, assisted
    if record.actionSnapshotFresh == true and record.actionSnapshotSlot == slot then
        record.actionSnapshotFresh = false
        actionType = record.actionSnapshotType
        id = record.actionSnapshotID
        subType = record.actionSnapshotSubType
        spellID = record.actionSnapshotSpellID
        interrupt = record.actionSnapshotInterrupt
        assisted = record.actionSnapshotAssisted
    else
        actionType, id, subType, spellID, interrupt, assisted =
            ReadActionSnapshot(slot, trustedSlot)
        StoreSnapshot(record, slot, actionType, id, subType, spellID, interrupt, assisted)
    end

    return ResolveSnapshot(record, slot, spellID, interrupt, assisted)
end

function Buttons:OnNativeActionChanged(button)
    local record = button and IG.ObservedButtons[button]
    if not record then
        record = self:ObserveButton(button, "native", { skipDirty = true })
        if not record then return end
    end

    local slot = ResolveNativeSlot(button)
    if not slot then
        -- Empty native buttons can receive repeated forced updates. Normalize the
        -- empty state once instead of waking the dirty worker every time.
        if StoreSnapshot(record, nil, nil, nil, nil, nil, false, nil) then
            record.actionSnapshotFresh = false
            IG:MarkButtonDirty(button)
            TrackHotPath("events.nativeActionBecameEmpty")
        end
        return
    end

    local actionType, id, subType, spellID, interrupt, assisted =
        ReadActionSnapshot(slot, true)
    if StoreSnapshot(record, slot, actionType, id, subType, spellID, interrupt, assisted) then
        record.actionSnapshotFresh = true
        IG:MarkButtonDirty(button)
        TrackHotPath("events.nativeActionIdentityChanged")
    elseif interrupt == false then
        TrackHotPath("events.nativeFastNonInterrupt")
    else
        TrackHotPath("events.nativeActionIdentityUnchanged")
    end
end
