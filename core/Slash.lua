local IG = _G.InterruptGlow
if not IG then return end

local Slash = {}
IG.Slash = Slash
IG:RegisterModule("Slash", Slash)

local lower = string.lower
local match = string.match
local format = string.format
local sort = table.sort

local function CountButtons()
    local observed = 0
    local interrupts = 0
    local overlays = 0
    for _, record in pairs(IG.ObservedButtons) do
        observed = observed + 1
        if record.isInterrupt then interrupts = interrupts + 1 end
        if record.overlay then overlays = overlays + 1 end
    end
    return observed, interrupts, overlays
end

local function PrintState()
    local observed, interrupts, overlays = CountButtons()
    local target = IG.CastState.target
    local focus = IG.CastState.focus

    IG:Print(format("version=%s enabled=%s spec=%s observed=%d interrupts=%d overlays=%d combat=%s",
        tostring(IG.version),
        tostring(IG.DB.enabled),
        tostring(IG.Data and IG.Data.activeSpecID),
        observed,
        interrupts,
        overlays,
        tostring(IG:IsInCombat())))
    IG:Print(format("target active=%s hostile=%s ni=%s castBarID=%s",
        tostring(target.active), tostring(target.hostile), tostring(target.niState), tostring(target.castBarID)))
    IG:Print(format("focus  active=%s hostile=%s ni=%s castBarID=%s",
        tostring(focus.active), tostring(focus.hostile), tostring(focus.niState), tostring(focus.castBarID)))
end

local function PrintStats()
    local keys = {}
    for key in pairs(IG.Stats) do keys[#keys + 1] = key end
    sort(keys)

    if #keys == 0 then
        IG:Print("No counters recorded.")
    else
        IG:Print("Counters:")
        for index = 1, #keys do
            local key = keys[index]
            IG:Print(format("  %-38s %s", key, tostring(IG.Stats[key])))
        end
    end

    if IG.Debug then
        local report = IG.Debug:ProfilerReport()
        for line in report:gmatch("[^\n]+") do IG:Print(line) end
    end
end

local function ResetStats()
    IG:WipeMap(IG.Stats)
    IG:Print("Counters reset.")
end

local function SetTestMode()
    if not IG.Glow then return end
    IG.Glow:SetTestMode(not IG.testMode)
    IG:Print("Test mode " .. (IG.testMode and "enabled" or "disabled") .. ".")
end

local function Rescan()
    if IG:IsInCombat() then
        IG:Print("Manual discovery is unavailable during combat.")
        return
    end

    if IG.Buttons then IG.Buttons:DiscoverAll(true) end
    if IG.CDM then IG.CDM:ObserveExistingItems() end
    if IG.Glow then IG.Glow:CreatePendingOverlays() end
    IG:MarkCastDirty()
    IG:MarkCooldownDirty(false)
    IG:Print("Targeted button discovery requested.")
end

local function PrintHelp()
    IG:Print("Commands:")
    IG:Print("  /iglow test          - toggle visual test mode")
    IG:Print("  /iglow state         - show normalized runtime state")
    IG:Print("  /iglow stats         - show counters and Blizzard profiler metrics")
    IG:Print("  /iglow stats reset   - reset counters")
    IG:Print("  /iglow rescan        - targeted OOC discovery; no global frame scan")
    IG:Print("  /iglow log show      - open copyable debug log")
    IG:Print("  /iglow log clear     - clear debug log")
    IG:Print("  /iglow enable|disable")
end

function Slash:Handle(message)
    message = message or ""
    local command, rest = match(message, "^%s*(%S*)%s*(.-)%s*$")
    command = lower(command or "")
    rest = lower(rest or "")

    if command == "test" then
        SetTestMode()
    elseif command == "state" then
        PrintState()
    elseif command == "stats" then
        if rest == "reset" then ResetStats() else PrintStats() end
    elseif command == "rescan" then
        Rescan()
    elseif command == "log" then
        if rest == "clear" and IG.Debug then
            IG.Debug:Clear()
            IG:Print("Debug log cleared.")
        elseif IG.Debug then
            IG.Debug:Show(IG.DB.debugKeep)
        end
    elseif command == "enable" then
        IG.DB.enabled = true
        -- Idle restricted polling sleeps while disabled. Take one fresh snapshot
        -- before a currently active cast is allowed to glow again.
        IG:MarkCooldownDirty(false)
        IG:MarkVisualDirty()
        IG:Print("Enabled.")
    elseif command == "disable" then
        IG.DB.enabled = false
        IG:MarkVisualDirty()
        IG:Print("Disabled.")
    else
        PrintHelp()
    end
end

SLASH_INTERRUPTGLOW1 = "/iglow"
SlashCmdList.INTERRUPTGLOW = function(message)
    Slash:Handle(message)
end
