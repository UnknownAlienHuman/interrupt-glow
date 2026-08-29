local IG = _G.InterruptGlow
if not IG or not IG.Buttons then return end

local Buttons = IG.Buttons
local _G = _G
local type = type

local buttonsByName = setmetatable({}, { __mode = "v" })

local originalObserveButtonForgeName = Buttons.ObserveButtonForgeName
function Buttons:ObserveButtonForgeName(buttonName)
    originalObserveButtonForgeName(self, buttonName)

    if type(buttonName) ~= "string" then return end
    local button = _G[buttonName]
    local record = button and IG.ObservedButtons[button]
    if record then
        record.buttonForgeName = buttonName
        buttonsByName[buttonName] = button
    end
end

local originalOnButtonForgeEvent = Buttons.OnButtonForgeEvent
function Buttons:OnButtonForgeEvent(event, buttonName)
    if event ~= "BUTTON_DEALLOCATED" then
        return originalOnButtonForgeEvent(self, event, buttonName)
    end

    if type(buttonName) ~= "string" then return end
    local button = _G[buttonName] or buttonsByName[buttonName]
    local record = button and IG.ObservedButtons[button]
    buttonsByName[buttonName] = nil
    if not record then return end

    local changed = record.buttonForgeObject ~= nil
        or record.buttonForgeMode ~= nil
        or record.buttonForgeMacroMode ~= nil
        or record.buttonForgeSpellID ~= nil
        or record.isInterrupt == true

    -- Provider callbacks may execute inside ButtonForge allocation/deallocation
    -- stacks. Clear only ordinary cached identity here; canonical unbind and
    -- addon-owned visual mutation occur in the next RunOnce reconciliation.
    record.buttonForgeObject = nil
    record.buttonForgeMode = nil
    record.buttonForgeMacroMode = nil
    record.buttonForgeSpellID = nil

    if changed then
        IG:MarkButtonDirty(button)
        IG:BumpStat("events.buttonForgeDeallocated")
    end
end

IG:RegisterModule("ButtonForgePolicy", {
    defersDeallocationReconcile = true,
    survivesEarlyGlobalRemoval = true,
})
