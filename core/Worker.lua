local IG = _G.InterruptGlow
if not IG then return end

local Worker = {}
IG.Worker = Worker
IG:RegisterModule("Worker", Worker)

local _G = _G
local type = type

local function GetOnUpdateMode()
    local enum = _G.Enum
    return enum and enum.OnUpdateMode or nil
end

local function SupportsMode(frame)
    local modes = GetOnUpdateMode()
    return modes ~= nil and frame ~= nil and type(frame.SetOnUpdateMode) == "function", modes
end

-- Current Retail 12.1 frames expose SetOnUpdateMode. The Show/Hide fallback is
-- retained only for test harnesses and an unexpected older client surface.
function Worker:Disable(frame)
    if not frame then return end

    local supported, modes = SupportsMode(frame)
    if supported then
        frame:SetOnUpdateMode(modes.Disabled)
    elseif type(frame.Hide) == "function" then
        frame:Hide()
    end
end

function Worker:RunOnce(frame)
    if not frame then return end

    local supported, modes = SupportsMode(frame)
    if supported then
        frame:SetOnUpdateMode(modes.RunOnce)
    elseif type(frame.Show) == "function" then
        frame:Show()
    end
end

function Worker:SetContinuous(frame, enabled)
    if not frame then return end

    local supported, modes = SupportsMode(frame)
    if supported then
        frame:SetOnUpdateMode(enabled and modes.RunAlways or modes.Disabled)
    elseif enabled then
        if type(frame.Show) == "function" then frame:Show() end
    elseif type(frame.Hide) == "function" then
        frame:Hide()
    end
end

function Worker:SupportsOnUpdateMode(frame)
    return SupportsMode(frame)
end
