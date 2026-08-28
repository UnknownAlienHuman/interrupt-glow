local IG = _G.InterruptGlow
if not IG then return end

local _G = _G
local type = type
local tostring = tostring

-- Internal per-path counters are diagnostic instrumentation, not production
-- logic. Keep them completely dormant unless debug logging or one explicit
-- diagnostic owner has acquired the counter window.
IG.profileCountersEnabled = false
IG.profileCounterOwner = nil

local function NormalizeOwner(owner)
    return type(owner) == "string" and owner ~= "" and owner or "manual"
end

function IG:BumpStat(key, amount)
    if self.DB.debug ~= true and self.profileCountersEnabled ~= true then return end
    if type(key) ~= "string" then return end

    amount = type(amount) == "number" and amount or 1
    self.Stats[key] = (self.Stats[key] or 0) + amount
end

function IG:StartProfileCounters(owner)
    owner = NormalizeOwner(owner)
    local currentOwner = self.profileCounterOwner
    if currentOwner ~= nil and currentOwner ~= owner then
        return false, currentOwner
    end

    self:WipeMap(self.Stats)
    self.profileCounterOwner = owner
    self.profileCountersEnabled = true
    return true, owner
end

function IG:StopProfileCounters(owner)
    owner = NormalizeOwner(owner)
    local currentOwner = self.profileCounterOwner
    if currentOwner ~= nil and currentOwner ~= owner then
        return false, currentOwner
    end

    self.profileCounterOwner = nil
    self.profileCountersEnabled = false
    return true, nil
end

function IG:ResetProfileCounters(owner)
    owner = NormalizeOwner(owner)
    local currentOwner = self.profileCounterOwner
    if currentOwner ~= nil and currentOwner ~= owner then
        return false, currentOwner
    end

    self:WipeMap(self.Stats)
    return true, currentOwner
end

function IG:Print(message)
    local chat = _G.DEFAULT_CHAT_FRAME
    if not chat or type(chat.AddMessage) ~= "function" then return end

    local text
    if not self.CanAccess(message) then
        text = "<inaccessible>"
    else
        local valueType = type(message)
        if message == nil then
            text = ""
        elseif valueType == "string" or valueType == "number" or valueType == "boolean" then
            text = tostring(message)
        else
            text = "<" .. valueType .. ">"
        end
    end

    chat:AddMessage("|cff66ccffInterruptGlow|r: " .. text)
end
