local IG = _G.InterruptGlow
if not IG then return end

local _G = _G
local type = type
local tostring = tostring

-- Internal per-path counters are diagnostic instrumentation, not production
-- logic. Keep them completely dormant unless debug logging or an explicit
-- session profile is enabled.
IG.profileCountersEnabled = false

function IG:BumpStat(key, amount)
    if self.DB.debug ~= true and self.profileCountersEnabled ~= true then return end
    if type(key) ~= "string" then return end

    amount = type(amount) == "number" and amount or 1
    self.Stats[key] = (self.Stats[key] or 0) + amount
end

function IG:StartProfileCounters()
    self:WipeMap(self.Stats)
    self.profileCountersEnabled = true
end

function IG:StopProfileCounters()
    self.profileCountersEnabled = false
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
