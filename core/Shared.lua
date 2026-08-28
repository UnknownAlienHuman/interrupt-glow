local IG = _G.InterruptGlow
if not IG then return end

local _G = _G
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local GetTime = _G.GetTime
local C_AddOns = _G.C_AddOns
local Worker = IG.Worker
local pcall = pcall
local type = type
local tostring = tostring
local tonumber = tonumber
local pairs = pairs
local next = next
local math_floor = math.floor

local CURRENT_SCHEMA = 3
local CURRENT_INTERFACE = 120100
local rawDB = type(InterruptGlowDB) == "table" and InterruptGlowDB or {}

local function ReadBoolean(key, defaultValue)
    local value = rawDB[key]
    if type(value) == "boolean" then return value end
    return defaultValue
end

local function ReadDebugKeep()
    local value = rawDB.debugKeep
    if type(value) ~= "number" or value ~= value then return 400 end
    value = math_floor(value)
    if value < 20 then return 20 end
    if value > 2000 then return 2000 end
    return value
end

-- SavedVariables contain preferences only. Rebuild a known-key schema on every
-- load so legacy slot/cooldown caches, corrupt values and arbitrary old keys do
-- not survive indefinitely. No runtime, frame or secret-capable value is copied.
local DB = {
    schema = CURRENT_SCHEMA,
    producerVersion = type(IG.version) == "string" and IG.version or "unknown",
    interface = CURRENT_INTERFACE,
    enabled = ReadBoolean("enabled", true),
    cdText = ReadBoolean("cdText", false),
    cdm = ReadBoolean("cdm", true),
    strictNI = ReadBoolean("strictNI", true),
    optimisticRestrictedCooldown = ReadBoolean("optimisticRestrictedCooldown", false),
    debug = ReadBoolean("debug", false),
    debugChat = ReadBoolean("debugChat", false),
    debugKeep = ReadDebugKeep(),
}
InterruptGlowDB = DB
IG.DB = DB

IG.ObservedButtons = IG.ObservedButtons or setmetatable({}, { __mode = "k" })
IG.PendingButtons = IG.PendingButtons or setmetatable({}, { __mode = "k" })
IG.InterruptRecords = IG.InterruptRecords or setmetatable({}, { __mode = "k" })
IG.AbilityStates = IG.AbilityStates or {}
IG.CastState = IG.CastState or {
    target = { active = false, hostile = false, niState = "none", castBarID = nil },
    focus = { active = false, hostile = false, niState = "none", castBarID = nil },
}
IG.Stats = IG.Stats or {}
IG.testMode = false
IG.runtimeInitialized = false
IG.playerLoginSeen = false

local canaccessvalue = _G.canaccessvalue
local function CanAccess(value)
    if type(canaccessvalue) ~= "function" then return true end
    return canaccessvalue(value) == true
end
IG.CanAccess = CanAccess

local function ReadIndex(container, key)
    return container[key]
end

function IG:ReadMember(container, key)
    if not CanAccess(container) or container == nil then return nil, false end
    local ok, value = pcall(ReadIndex, container, key)
    if not ok or not CanAccess(value) then return nil, false end
    return value, true
end

function IG:AsNumber(value)
    if not CanAccess(value) then return nil end
    local valueType = type(value)
    if valueType == "number" then return value end
    if valueType == "string" then return tonumber(value) end
    return nil
end

function IG:AsBoolean(value)
    if not CanAccess(value) then return nil end
    if value == true then return true end
    if value == false then return false end
    return nil
end

function IG:Now()
    if type(GetTime) ~= "function" then return 0 end
    local value = GetTime()
    if CanAccess(value) and type(value) == "number" then return value end
    return 0
end

function IG:IsInCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    return InCombatLockdown() == true
end

function IG:IsAddOnFullyLoaded(addOnName)
    if not C_AddOns or type(C_AddOns.IsAddOnLoaded) ~= "function" then return false end
    local ok, _loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, addOnName)
    return ok and loaded == true
end

function IG:Print(message)
    local chat = _G.DEFAULT_CHAT_FRAME
    if not chat or not chat.AddMessage then return end
    chat:AddMessage("|cff66ccffInterruptGlow|r: " .. tostring(message or ""))
end

function IG:BumpStat(key, amount)
    amount = amount or 1
    self.Stats[key] = (self.Stats[key] or 0) + amount
end

function IG:WipeMap(map)
    for key in pairs(map) do map[key] = nil end
end

function IG:NeedsReadinessRuntime()
    if DB.enabled ~= true then return false end
    if DB.cdText == true then return true end

    local glow = self.Glow
    return glow ~= nil
        and type(glow.HasRelevantCast) == "function"
        and glow:HasRelevantCast() == true
end

local function MarkActiveAbilitiesReadinessPending()
    for _, ability in pairs(IG.AbilityStates) do
        if next(ability.records) ~= nil then
            ability.readinessPending = true
        end
    end
end

IG._dirty = IG._dirty or {
    spec = false,
    allButtons = false,
    cast = false,
    cooldown = false,
    visual = false,
    pruneCaches = false,
}

local flushFrame = IG.flushFrame
if not flushFrame then
    flushFrame = CreateFrame("Frame")
    IG.flushFrame = flushFrame
end

local flushScheduled = false

local function DisableFlushWorker()
    flushScheduled = false
    if Worker then
        Worker:Disable(flushFrame)
    elseif flushFrame.Hide then
        flushFrame:Hide()
    end
end

local function ScheduleFlushWorker()
    if flushScheduled then return end
    flushScheduled = true
    if Worker then
        Worker:RunOnce(flushFrame)
    elseif flushFrame.Show then
        flushFrame:Show()
    end
end

DisableFlushWorker()

function IG:RequestFlush()
    ScheduleFlushWorker()
end

function IG:MarkButtonDirty(button)
    if not button then return end
    self.PendingButtons[button] = true
    self:RequestFlush()
end

function IG:MarkSpecDirty()
    self._dirty.spec = true
    self:RequestFlush()
end

function IG:MarkAllButtonsDirty()
    self._dirty.allButtons = true
    self:RequestFlush()
end

function IG:MarkCastDirty()
    self._dirty.cast = true
    self:RequestFlush()
end

function IG:MarkCooldownDirty(fromSpellCooldownEvent)
    if not self:NeedsReadinessRuntime() then
        self._dirty.cooldown = false
        if self.Cooldown and self.Cooldown.ClearGCDHints then self.Cooldown:ClearGCDHints() end
        return false
    end

    self._dirty.cooldown = true
    MarkActiveAbilitiesReadinessPending()
    if not fromSpellCooldownEvent and self.Cooldown and self.Cooldown.ClearGCDHints then
        self.Cooldown:ClearGCDHints()
    end
    self:RequestFlush()
    return true
end

function IG:MarkVisualDirty()
    self._dirty.visual = true
    self:RequestFlush()
end

function IG:HasDirtyWork()
    local dirty = self._dirty
    return dirty.spec
        or dirty.allButtons
        or dirty.cast
        or dirty.cooldown
        or dirty.visual
        or dirty.pruneCaches
        or next(self.PendingButtons) ~= nil
end

function IG:Flush()
    local dirty = self._dirty
    local Buttons = self.Buttons
    local CastTracking = self.CastTracking
    local Cooldown = self.Cooldown
    local Glow = self.Glow

    if dirty.spec then
        dirty.spec = false
        local specChanged = false
        if self.Data then
            local _specID, changed = self.Data:RefreshActiveSpec()
            specChanged = changed == true
        end
        dirty.pruneCaches = dirty.pruneCaches or specChanged
        dirty.allButtons = true
        dirty.cooldown = self:NeedsReadinessRuntime()
        if dirty.cooldown then MarkActiveAbilitiesReadinessPending() end
    end

    if dirty.allButtons then
        dirty.allButtons = false
        self:WipeMap(self.PendingButtons)
        if Buttons then Buttons:ReconcileAll() end
    elseif next(self.PendingButtons) ~= nil then
        if Buttons then Buttons:ReconcilePending() else self:WipeMap(self.PendingButtons) end
    end

    if dirty.pruneCaches then
        dirty.pruneCaches = false
        if Buttons and Buttons.PruneDormantAbilities then Buttons:PruneDormantAbilities() end
        if Cooldown and Cooldown.ResetCaches then Cooldown:ResetCaches() end
    end

    if dirty.cast then
        dirty.cast = false
        if CastTracking then CastTracking:RefreshAll() end
    end

    if dirty.cooldown then
        dirty.cooldown = false
        if self:NeedsReadinessRuntime() and Cooldown then
            Cooldown:RefreshAll()
        elseif Cooldown and Cooldown.ClearGCDHints then
            Cooldown:ClearGCDHints()
        end
    end

    if dirty.visual then
        dirty.visual = false
        if Glow then Glow:RefreshAll() end
    end

    if self:HasDirtyWork() then
        self:RequestFlush()
    else
        DisableFlushWorker()
    end
end

flushFrame:SetScript("OnUpdate", function()
    -- RunOnce resets itself before execution. The fallback worker is hidden here.
    DisableFlushWorker()
    IG:Flush()
end)
