local IG = _G.InterruptGlow
if not IG then return end

local _G = _G
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local GetTime = _G.GetTime
local C_AddOns = _G.C_AddOns
local pcall = pcall
local type = type
local tostring = tostring
local tonumber = tonumber
local pairs = pairs

if type(InterruptGlowDB) ~= "table" then InterruptGlowDB = {} end
local DB = InterruptGlowDB

if DB.schema ~= 2 then
    DB.slots = nil
    DB.localCD = nil
    DB.schema = 2
end

if DB.enabled == nil then DB.enabled = true end
if DB.cdText == nil then DB.cdText = false end
if DB.cdm == nil then DB.cdm = true end
if DB.strictNI == nil then DB.strictNI = true end
if DB.optimisticRestrictedCooldown == nil then DB.optimisticRestrictedCooldown = false end
if DB.debug == nil then DB.debug = false end
if DB.debugChat == nil then DB.debugChat = false end
if DB.debugKeep == nil then DB.debugKeep = 400 end
if DB.debugAutoShow == nil then DB.debugAutoShow = false end

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

-- C_AddOns.IsAddOnLoaded returns (loadedOrLoading, loaded). The first result
-- must not be used as an attach gate because the add-on may still be executing.
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

IG._dirty = IG._dirty or {
    spec = false,
    allButtons = false,
    cast = false,
    cooldown = false,
    visual = false,
}

local flushFrame = IG.flushFrame
if not flushFrame then
    flushFrame = CreateFrame("Frame")
    flushFrame:Hide()
    IG.flushFrame = flushFrame
end

function IG:RequestFlush()
    flushFrame:Show()
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
    if DB.enabled ~= true then
        self._dirty.cooldown = false
        if self.Cooldown and self.Cooldown.ClearGCDHints then self.Cooldown:ClearGCDHints() end
        return
    end

    self._dirty.cooldown = true
    if not fromSpellCooldownEvent and self.Cooldown and self.Cooldown.ClearGCDHints then
        -- A different invalidation in the same frame makes an earlier
        -- SPELL_UPDATE_COOLDOWN hint potentially stale. Failing closed is safer.
        self.Cooldown:ClearGCDHints()
    end
    self:RequestFlush()
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
        if self.Data then self.Data:RefreshActiveSpec() end
        dirty.allButtons = true
        dirty.cooldown = DB.enabled == true
    end

    if dirty.allButtons then
        dirty.allButtons = false
        self:WipeMap(self.PendingButtons)
        if Buttons then Buttons:ReconcileAll() end
    elseif next(self.PendingButtons) ~= nil then
        if Buttons then Buttons:ReconcilePending() else self:WipeMap(self.PendingButtons) end
    end

    if dirty.cast then
        dirty.cast = false
        if CastTracking then CastTracking:RefreshAll() end
    end

    if dirty.cooldown then
        dirty.cooldown = false
        if DB.enabled == true and Cooldown then
            Cooldown:RefreshAll()
        elseif Cooldown and Cooldown.ClearGCDHints then
            Cooldown:ClearGCDHints()
        end
    end

    if dirty.visual then
        dirty.visual = false
        if Glow then Glow:RefreshAll() end
    end

    if self:HasDirtyWork() then self:RequestFlush() end
end

flushFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    IG:Flush()
end)
