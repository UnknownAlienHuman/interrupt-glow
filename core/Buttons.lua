local IG = _G.InterruptGlow
if not IG then return end

local Private = IG.Private
local DB = Private.DB
local Debug = Private.Debug
local IsSecret = Private.IsSecret
local SafeNow = Private.SafeNow
local SpellName = Private.SpellName
local SpellTexture = Private.SpellTexture
local SpellKnown = Private.SpellKnown
local INTERRUPTS_BY_CLASS = Private.INTERRUPTS_BY_CLASS
local WipeArray = Private.WipeArray
local WipeMap = Private.WipeMap
local AddUniqueButton = Private.AddUniqueButton
local EnumerateFrames = Private.EnumerateFrames
local GetActionInfo = Private.GetActionInfo
local GetMacroInfo = Private.GetMacroInfo
local GetMacroSpell = Private.GetMacroSpell
local InCombatLockdown = Private.InCombatLockdown
local C_Timer = Private.C_Timer
local strlower = Private.strlower
local GuardedCall = Private.GuardedCall
local GetButtonCDText = function(btn)
    return Private.GetButtonCDText and Private.GetButtonCDText(btn) or nil
end

local MAX_ACTION_SLOTS = 540

local function MatchesBoundaryChar(char, pattern)
    return type(char) == "string" and char ~= "" and char:match(pattern) ~= nil
end

local function FindTokenWithBoundaries(text, token, boundaryPattern)
    if type(text) ~= "string" or text == "" then return false end
    if type(token) ~= "string" or token == "" then return false end

    local startIndex = 1
    while true do
        local s, e = text:find(token, startIndex, true)
        if not s then
            return false
        end

        local before = (s > 1) and text:sub(s - 1, s - 1) or nil
        local after = (e < #text) and text:sub(e + 1, e + 1) or nil
        if not MatchesBoundaryChar(before, boundaryPattern) and not MatchesBoundaryChar(after, boundaryPattern) then
            return true
        end

        startIndex = s + 1
    end
end

local function FindInterruptSpellIDInText(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local lowerText = strlower(text)
    for sid in pairs(IG.interruptSpellSet) do
        if FindTokenWithBoundaries(lowerText, tostring(sid), "%d") then
            return sid
        end
    end

    local names = {}
    local count = 0
    for name, sid in pairs(IG.interruptNameToID) do
        count = count + 1
        names[count] = { name = name, sid = sid }
    end

    table.sort(names, function(a, b)
        return #a.name > #b.name
    end)

    for i = 1, count do
        local entry = names[i]
        if FindTokenWithBoundaries(lowerText, entry.name, "[%w\128-\255]") then
            return entry.sid
        end
    end

    return nil
end

local function MacroMatchesInterrupt(macroId)
    if not macroId then return false end

    if GetMacroSpell then
        local ms = GetMacroSpell(macroId)
        if ms then
            if type(ms) == "number" and IG.interruptSpellSet[ms] then
                return true
            elseif type(ms) == "string" and IG.interruptNameToID[strlower(ms)] then
                return true
            end
        end
    end

    if not GetMacroInfo then return false end
    local _, _, body = GetMacroInfo(macroId)
    if not body or body == "" then return false end

    return FindInterruptSpellIDInText(body) ~= nil
end

local function ResolveInterruptSpellIDFromMacro(macroId)
    if not macroId then return nil end

    if GetMacroSpell then
        local ms = GetMacroSpell(macroId)
        if type(ms) == "number" and IG.interruptSpellSet[ms] then
            return ms
        elseif type(ms) == "string" then
            local sid = IG.interruptNameToID[strlower(ms)]
            if sid then return sid end
        end
    end

    if GetMacroInfo then
        local _, _, body = GetMacroInfo(macroId)
        if type(body) == "string" and body ~= "" then
            return FindInterruptSpellIDInText(body)
        end
    end

    return nil
end

local function SlotLooksLikeInterrupt(slot)
    local actionType, id = GetActionInfo(slot)

    if actionType == "spell" and type(id) == "number" and IG.interruptSpellSet[id] then
        return true, id, "spell:" .. tostring(id)
    end

    if actionType == "macro" and id then
        if MacroMatchesInterrupt(id) then
            local sid = ResolveInterruptSpellIDFromMacro(id)
            return true, sid, "macro:" .. tostring(id)
        end
        if type(id) == "number" and IG.interruptSpellSet[id] then
            return true, id, "macro-spellid:" .. tostring(id)
        end
        return false, nil, "macro-no-interrupt:" .. tostring(id)
    end

    if actionType == nil then
        return false, nil, "empty"
    end

    return false, nil, "type=" .. tostring(actionType) .. " id=" .. tostring(id)
end

function IG:ValidateInterruptSlot(slot, now)
    if type(slot) ~= "number" then return false, nil, "no-slot" end
    now = now or SafeNow()
    self._slotValidateCache = self._slotValidateCache or {}
    local cache = self._slotValidateCache[slot]
    if cache and type(cache.ts) == "number" and (now - cache.ts) < 0.75 then
        return cache.ok, cache.sid, cache.reason
    end

    local ok, sid, reason = SlotLooksLikeInterrupt(slot)
    self._slotValidateCache[slot] = { ts = now, ok = ok, sid = sid, reason = reason }
    return ok, sid, reason
end

function IG:ClearSlotValidationCache()
    if not self._slotValidateCache then return end
    for key in pairs(self._slotValidateCache) do
        self._slotValidateCache[key] = nil
    end
end

local function BuildInterruptCaches()
    WipeMap(IG.interruptSpellSet)
    WipeMap(IG.interruptNameToID)
    WipeArray(IG.interruptTokens)

    IG.interruptSpellID = nil

    local list = INTERRUPTS_BY_CLASS[IG.class]
    if not list then return end

    for i = 1, #list do
        local spellID = list[i]
        if spellID then
            IG.interruptSpellSet[spellID] = true
            IG.interruptTokens[#IG.interruptTokens + 1] = tostring(spellID)

            local name = SpellName(spellID)
            if name then
                local lowerName = strlower(name)
                IG.interruptNameToID[lowerName] = IG.interruptNameToID[lowerName] or spellID
                IG.interruptTokens[#IG.interruptTokens + 1] = lowerName
            end

            if not IG.interruptSpellID and SpellKnown(spellID) then
                IG.interruptSpellID = spellID
            end
        end
    end
end

local function ScanActionSlots()
    WipeMap(IG.trackedSlots)
    WipeMap(IG.slotSpellID)

    local foundSlots = {}
    local foundSpell = {}
    local count = 0

    for slot = 1, MAX_ACTION_SLOTS do
        local ok, sid = SlotLooksLikeInterrupt(slot)
        if ok then
            IG.trackedSlots[slot] = true
            IG.slotSpellID[slot] = sid
            count = count + 1
            foundSlots[count] = slot
            foundSpell[count] = sid
        end
    end

    DB.slots = foundSlots
    IG.primarySlot = foundSlots[1]
    IG._slotResolvedSpellID = foundSpell[1]

    Debug(("Rescan: slots=%d primarySlot=%s slotSpellID=%s")
        :format(count, tostring(IG.primarySlot), tostring(IG._slotResolvedSpellID)))
end

local function GetButtonActionSlot(btn)
    local t = type(btn)
    if t ~= "table" and t ~= "userdata" then return nil end

    local action = btn.action
    if type(action) == "number" then return action end
    if type(action) == "string" then
        local num = tonumber(action)
        if num then return num end
    end

    action = btn._state_action
    if type(action) == "number" then return action end
    if type(action) == "string" then
        local num = tonumber(action)
        if num then return num end
    end

    if btn.GetAttribute then
        action = btn:GetAttribute("action")
        if type(action) == "number" then return action end
        if type(action) == "string" then
            local num = tonumber(action)
            if num then return num end
        end
    end

    local getPaged = _G.ActionButton_GetPagedID
    if type(getPaged) == "function" then
        local ok, slot = GuardedCall("buttons:get-paged-id", getPaged, btn)
        if ok and type(slot) == "number" then return slot end
    end

    return nil
end

local function ButtonAttributesLookLikeInterrupt(btn)
    if not btn.GetAttribute then return false, nil, nil end

    local actionType = btn:GetAttribute("type") or btn:GetAttribute("type1")

    if actionType == "spell" then
        local spell = btn:GetAttribute("spell") or btn:GetAttribute("spell1")
        if type(spell) == "number" and IG.interruptSpellSet[spell] then
            return true, "attr spellID", spell
        end
        if type(spell) == "string" then
            local sid = IG.interruptNameToID[spell:lower()]
            if sid then
                return true, "attr spell name", sid
            end
        end
    elseif actionType == "macro" then
        local text = btn:GetAttribute("macrotext") or btn:GetAttribute("macrotext1")
        if type(text) == "string" and text ~= "" then
            local sid = FindInterruptSpellIDInText(text)
            if sid then
                return true, "attr macrotext", sid
            end
        end
    end

    local macroText = btn:GetAttribute("macrotext") or btn:GetAttribute("macrotext1")
    if type(macroText) == "string" and macroText ~= "" then
        local sid = FindInterruptSpellIDInText(macroText)
        if sid then
            return true, "attr macrotext (no type)", sid
        end
    end

    local macroId = btn:GetAttribute("macro") or btn:GetAttribute("macro1")
    if macroId then
        local sid = ResolveInterruptSpellIDFromMacro(macroId)
        if sid or MacroMatchesInterrupt(macroId) then
            return true, "attr macro id", sid
        end
    end

    local spell = btn:GetAttribute("spell") or btn:GetAttribute("spell1")
    if type(spell) == "number" and IG.interruptSpellSet[spell] then
        return true, "attr spellID (no type)", spell
    end
    if type(spell) == "string" then
        local sid = IG.interruptNameToID[spell:lower()]
        if sid then
            return true, "attr spell name (no type)", sid
        end
    end

    return false, nil, nil
end

local NAMED_BUTTON_SETS = {
    { prefix = "ActionButton", count = 12 },
    { prefix = "MultiBarBottomLeftButton", count = 12 },
    { prefix = "MultiBarBottomRightButton", count = 12 },
    { prefix = "MultiBarRightButton", count = 12 },
    { prefix = "MultiBarLeftButton", count = 12 },
    { prefix = "MultiBar5Button", count = 12 },
    { prefix = "MultiBar6Button", count = 12 },
    { prefix = "MultiBar7Button", count = 12 },
    { prefix = "MultiBar8Button", count = 12 },
    { prefix = "MultiBar9Button", count = 12 },
    { prefix = "MultiBar10Button", count = 12 },
    { prefix = "PTR4ActionBarButton", count = 12 },
    { prefix = "PTR5ActionBarButton", count = 12 },
    { prefix = "PTR6ActionBarButton", count = 12 },
    { prefix = "BT4Button", count = 180 },
    { prefix = "DominosActionButton", count = 180 },
}

local function MapButtonsFromNamedBars()
    for _, set in ipairs(NAMED_BUTTON_SETS) do
        for i = 1, set.count do
            local btn = _G[set.prefix .. i]
            if btn then
                local slot = GetButtonActionSlot(btn)
                if slot and IG.trackedSlots[slot] then
                    AddUniqueButton(btn)
                end
            end
        end
    end

    for bar = 1, 10 do
        for i = 1, 12 do
            local btn = _G["ElvUI_Bar" .. bar .. "Button" .. i]
            if btn then
                local slot = GetButtonActionSlot(btn)
                if slot and IG.trackedSlots[slot] then
                    AddUniqueButton(btn)
                end
            end
        end
    end

    local extra = _G.ExtraActionButton1
    if extra then
        local slot = GetButtonActionSlot(extra)
        if slot and IG.trackedSlots[slot] then
            AddUniqueButton(extra)
        end
    end
end

local function ButtonForgeActionMatchesInterrupt(api, buttonName)
    if not api or type(api.GetButtonActionInfo) ~= "function" then return false, nil end
    local actionType, id = api.GetButtonActionInfo(buttonName)
    if actionType == "spell" and type(id) == "number" and IG.interruptSpellSet[id] then
        return true, id
    end
    if actionType == "macro" and id and MacroMatchesInterrupt(id) then
        return true, ResolveInterruptSpellIDFromMacro(id)
    end
    return false, nil
end

local function MapButtonsFromButtonForge()
    local api = _G.ButtonForge_API1
    if not api or type(api.GetButtonFrameNames) ~= "function" then return end
    if api.GetButtonForgeInitialised and not api.GetButtonForgeInitialised() then return end

    local names = api.GetButtonFrameNames()
    if type(names) ~= "table" then return end

    for i = 1, #names do
        local name = names[i]
        local btn = type(name) == "string" and _G[name] or nil
        if btn then
            local slot = GetButtonActionSlot(btn)
            if slot and IG.trackedSlots[slot] then
                AddUniqueButton(btn)
            else
                local ok, _, sid = ButtonAttributesLookLikeInterrupt(btn)
                if ok then
                    AddUniqueButton(btn)
                    IG._attrResolvedSpellID = IG._attrResolvedSpellID or sid
                else
                    local ok2, sid2 = ButtonForgeActionMatchesInterrupt(api, name)
                    if ok2 then
                        AddUniqueButton(btn)
                        IG._attrResolvedSpellID = IG._attrResolvedSpellID or sid2
                    end
                end
            end
        end
    end
end

local function EnumerateAndMapButtons()
    if not EnumerateFrames then return end

    local frame = EnumerateFrames()
    while frame do
        if frame.GetObjectType then
            local objectType = frame:GetObjectType()
            if objectType == "CheckButton" or objectType == "Button" then
                local slot = GetButtonActionSlot(frame)
                if slot and IG.trackedSlots[slot] then
                    AddUniqueButton(frame)
                else
                    local ok, _, sid = ButtonAttributesLookLikeInterrupt(frame)
                    if ok then
                        AddUniqueButton(frame)
                        IG._attrResolvedSpellID = IG._attrResolvedSpellID or sid
                    end
                end
            end
        end

        frame = EnumerateFrames(frame)
    end
end

local function ResolvePrimaryInterruptSpellID()
    if IG._slotResolvedSpellID then return IG._slotResolvedSpellID end

    for _, slot in ipairs(DB.slots) do
        local sid = IG.slotSpellID[slot]
        if sid then return sid end
    end

    if IG._attrResolvedSpellID then return IG._attrResolvedSpellID end
    if IG.interruptSpellID then return IG.interruptSpellID end
    return nil
end

function IG:RescanInterruptButtons(deep)
    if InCombatLockdown and InCombatLockdown() then
        self.needsRescan = true
        Debug("Rescan deferred (in combat).")
        return
    end

    self.needsRescan = false

    self:SetGlow(false)
    WipeArray(self.trackedButtons)
    WipeArray(self.extraButtons)
    self.cdmButton = nil
    self._cdmLastScan = nil
    self._slotResolvedSpellID = nil
    self._attrResolvedSpellID = nil

    ScanActionSlots()
    MapButtonsFromNamedBars()
    MapButtonsFromButtonForge()

    if deep or #self.trackedButtons == 0 then
        EnumerateAndMapButtons()
    end

    self.primaryButton = nil
    if self.primarySlot then
        for i = 1, #self.trackedButtons do
            local btn = self.trackedButtons[i]
            local slot = GetButtonActionSlot(btn)
            if slot == self.primarySlot then
                self.primaryButton = btn
                break
            end
        end
    end
    if not self.primaryButton then
        self.primaryButton = self.trackedButtons[1]
    end

    local oldSpellID = self.interruptSpellID
    self.interruptSpellID = ResolvePrimaryInterruptSpellID()
    if oldSpellID ~= self.interruptSpellID and self._localCD then
        self._localCD.nextReadyTime = nil
        self._localCD.lastCastAt = nil
        self._localCD.armed = false
    end
    self:UpdateLocalCooldownBase()

    Debug(("Buttons=%d Slots=%d interruptSpellID=%s")
        :format(#self.trackedButtons, #DB.slots, tostring(self.interruptSpellID)))
end

function IG:HookButtonForgeCallbacks()
    if self._bfCallbackRegistered then return end
    local api = _G.ButtonForge_API1
    if not api or type(api.RegisterCallback) ~= "function" then return end

    self._bfCallbackRegistered = true
    local function OnButtonForgeEvent(_, event)
        if event == "INITIALISED" or event == "BUTTON_ALLOCATED" or event == "BUTTON_DEALLOCATED" then
            IG:RescanInterruptButtons(true)
            IG:HookCooldownDoneFrames()
            if DB.cdText then IG:PrepareCDText() end
            IG:MarkReadyDirty("buttonforge")
        end
    end
    api.RegisterCallback(OnButtonForgeEvent, self)
end

local function GetFrameSpellID(frame)
    if not frame then return nil end

    local sid = frame.spellID or frame.spellId
    if type(sid) == "number" then return sid end

    if frame.data and type(frame.data) == "table" then
        sid = frame.data.spellID or frame.data.spellId
        if type(sid) == "number" then return sid end
    end

    if frame.cooldownInfo and type(frame.cooldownInfo) == "table" then
        sid = frame.cooldownInfo.spellID or frame.cooldownInfo.spellId
        if type(sid) == "number" then return sid end
    end

    if frame.GetSpellID then
        local ok, value = GuardedCall("buttons:get-spell-id", frame.GetSpellID, frame)
        if ok and type(value) == "number" then return value end
    end

    if frame.GetAttribute then
        sid = frame:GetAttribute("spell")
        if type(sid) == "number" then return sid end
    end

    return nil
end

local function GetFrameIconTexture(frame)
    if not frame then return nil end

    local icon = frame.Icon or frame.icon or frame.IconTexture or frame.iconTexture
    if icon and icon.GetTexture then
        local ok, texture = GuardedCall("buttons:get-icon-texture", icon.GetTexture, icon)
        if ok then return texture end
    end

    if frame.GetNormalTexture then
        local ok, normal = GuardedCall("buttons:get-normal-texture", frame.GetNormalTexture, frame)
        if ok and normal and normal.GetTexture then
            local ok2, texture = GuardedCall("buttons:get-normal-texture-file", normal.GetTexture, normal)
            if ok2 then return texture end
        end
    end

    return nil
end

local function CollectChildrenForSpellOrIcon(root, spellID, spellTexture, maxNodes, out, seen)
    if not root then return end
    out = out or {}
    seen = seen or {}

    local queue = { root }
    local index = 1
    local nodes = 0
    maxNodes = maxNodes or 6000

    while index <= #queue and nodes < maxNodes do
        local frame = queue[index]
        index = index + 1
        nodes = nodes + 1

        if frame and frame.GetObjectType then
            local objectType = frame:GetObjectType()
            if objectType == "Button" or objectType == "Frame" then
                local sid = GetFrameSpellID(frame)
                if sid and not IsSecret(sid) and sid == spellID then
                    if not seen[frame] then
                        out[#out + 1] = frame
                        seen[frame] = true
                    end
                elseif spellTexture ~= nil then
                    local texture = GetFrameIconTexture(frame)
                    if texture ~= nil and not IsSecret(texture) and tostring(texture) == tostring(spellTexture) then
                        if not seen[frame] then
                            out[#out + 1] = frame
                            seen[frame] = true
                        end
                    end
                end
            end
        end

        if frame and frame.GetChildren then
            local children = { frame:GetChildren() }
            for i = 1, #children do
                queue[#queue + 1] = children[i]
            end
        end
    end
end

local function HideGlowSafe(btn)
    local hideGlow = Private.HideGlow
    if hideGlow then
        hideGlow(btn)
    end
end

function IG:TryFindCDMButton()
    if not DB.cdm then return end
    if not self.interruptSpellID then return end
    if InCombatLockdown and InCombatLockdown() then return end

    local now = SafeNow()
    if self._cdmLastScan and (now - self._cdmLastScan) < 1.0 then
        return
    end
    self._cdmLastScan = now

    local roots = {}
    local function AddRoot(root)
        if not root then return end
        if root.IsForbidden and root:IsForbidden() then return end
        roots[#roots + 1] = root
    end

    AddRoot(_G.EssentialCooldownViewer)
    AddRoot(_G.UtilityCooldownViewer)
    AddRoot(_G.BuffIconCooldownViewer)

    if #roots == 0 then return end

    local spellID = self.interruptSpellID
    local spellTex = SpellTexture(spellID)
    local found = {}
    local seen = {}
    for i = 1, #roots do
        CollectChildrenForSpellOrIcon(roots[i], spellID, spellTex, 6000, found, seen)
    end

    local changed = false
    if #found ~= #self.extraButtons then
        changed = true
    else
        for i = 1, #found do
            if found[i] ~= self.extraButtons[i] then
                changed = true
                break
            end
        end
    end

    if changed then
        WipeArray(self.extraButtons)
        for i = 1, #found do
            self.extraButtons[#self.extraButtons + 1] = found[i]
        end
        self.cdmButton = found[1]
        Debug(("CDM buttons updated: %d"):format(#found))
        self:HookCooldownDoneFrames()
        if DB.cdText then self:PrepareCDText() end
        self:MarkReadyDirty("cdm-scan")
    end
end

function IG:ClearExtraButtons()
    if self.glowActive then
        for i = 1, #self.extraButtons do
            HideGlowSafe(self.extraButtons[i])
        end
    end

    for i = 1, #self.extraButtons do
        local fs = GetButtonCDText(self.extraButtons[i])
        if fs then fs:Hide() end
    end

    WipeArray(self.extraButtons)
    self.cdmButton = nil
    self._cdmLastScan = nil
end

Private.BuildInterruptCaches = BuildInterruptCaches
Private.GetButtonActionSlot = GetButtonActionSlot
