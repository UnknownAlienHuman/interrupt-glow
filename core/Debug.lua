local IG = _G.InterruptGlow
if not IG then return end

local Debug = {
    entries = {},
    nextIndex = 1,
    count = 0,
    window = nil,
}
IG.Debug = Debug
IG:RegisterModule("Debug", Debug)

local format = string.format
local concat = table.concat
local math_max = math.max
local type = type
local tostring = tostring

local function SafeText(value, fallback)
    if not IG.CanAccess(value) then return "<inaccessible>" end
    if value == nil then return fallback or "" end

    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end
    return "<" .. valueType .. ">"
end

function Debug:Log(category, message)
    if not IG.DB.debug then return end

    local keep = tonumber(IG.DB.debugKeep) or 400
    if keep < 20 then keep = 20 end

    local line = format(
        "%9.3f  %-10s  %s",
        IG:Now(),
        SafeText(category, "debug"),
        SafeText(message, "")
    )
    self.entries[self.nextIndex] = line
    self.nextIndex = self.nextIndex + 1
    if self.nextIndex > keep then self.nextIndex = 1 end
    self.count = math.min((self.count or 0) + 1, keep)

    if IG.DB.debugChat then IG:Print(line) end
end

function Debug:Clear()
    IG:WipeMap(self.entries)
    self.nextIndex = 1
    self.count = 0
end

function Debug:GetLines(limit)
    local total = self.count or 0
    if total == 0 then return "Interrupt Glow log is empty." end

    limit = tonumber(limit) or total
    if limit < 1 then limit = 1 end
    if limit > total then limit = total end

    local keep = tonumber(IG.DB.debugKeep) or 400
    local first = self.nextIndex - total
    if first <= 0 then first = first + keep end

    local skip = total - limit
    local output = {}
    local outCount = 0
    for offset = skip, total - 1 do
        local index = first + offset
        while index > keep do index = index - keep end
        local line = self.entries[index]
        if line then
            outCount = outCount + 1
            output[outCount] = line
        end
    end

    return concat(output, "\n")
end

local function CreateDebugWindow()
    local frame = CreateFrame("Frame", "InterruptGlowDebugWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(760, 520)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    if frame.TitleText then frame.TitleText:SetText("Interrupt Glow") end

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 38)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(700)
    edit:SetTextInsets(6, 6, 6, 6)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(edit)

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(90, 22)
    close:SetPoint("BOTTOMRIGHT", -12, 10)
    close:SetText("Close")
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.EditBox = edit
    return frame
end

function Debug:ShowText(title, text)
    if not self.window then
        if IG:IsInCombat() then
            IG:Print("The copyable report window can be created after combat.")
            return
        end
        self.window = CreateDebugWindow()
    end

    title = SafeText(title, "Interrupt Glow")
    text = SafeText(text, "")

    if self.window.TitleText then self.window.TitleText:SetText(title) end

    local lines = 1
    for _ in text:gmatch("\n") do lines = lines + 1 end
    self.window.EditBox:SetHeight(math_max(440, lines * 15 + 20))
    self.window.EditBox:SetText(text)
    self.window.EditBox:HighlightText(0, 0)
    self.window:Show()
end

function Debug:Show(limit)
    self:ShowText("Interrupt Glow Debug Log", self:GetLines(limit))
end

function Debug:ProfilerReport()
    local profiler = _G.C_AddOnProfiler
    local enum = _G.Enum and _G.Enum.AddOnProfilerMetric
    if not profiler or not enum or type(profiler.GetAddOnMetric) ~= "function" then
        return "C_AddOnProfiler is unavailable."
    end

    local metrics = {
        { "RecentAverageTime", enum.RecentAverageTime },
        { "EncounterAverageTime", enum.EncounterAverageTime },
        { "LastTime", enum.LastTime },
        { "PeakTime", enum.PeakTime },
        { "CountTimeOver1Ms", enum.CountTimeOver1Ms },
        { "CountTimeOver5Ms", enum.CountTimeOver5Ms },
        { "CountTimeOver10Ms", enum.CountTimeOver10Ms },
        { "CountTimeOver50Ms", enum.CountTimeOver50Ms },
    }

    local output = {}
    local count = 0
    for index = 1, #metrics do
        local entry = metrics[index]
        local ok, value = pcall(profiler.GetAddOnMetric, IG.name, entry[2])
        if ok and IG.CanAccess(value) then
            count = count + 1
            output[count] = format("%-24s %s", entry[1], SafeText(value, "0"))
        end
    end

    if count == 0 then return "No profiler metrics returned for " .. IG.name .. "." end
    return concat(output, "\n")
end
