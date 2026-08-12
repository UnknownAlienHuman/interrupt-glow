local IG = _G.InterruptGlow
if not IG then return end

local Private = IG.Private
local DB = Private.DB
local Print = Private.Print
local SafeNow = Private.SafeNow
local CreateFrame = Private.CreateFrame
local C_Timer = Private.C_Timer

IG.Debug = IG.Debug or {}

do
    local D = IG.Debug

    D.buf = D.buf or {}
    D.head = D.head or 0
    D.count = D.count or 0

    local function NowStr()
        local t = SafeNow()
        if type(t) ~= "number" then return "0.000" end
        return string.format("%.3f", t)
    end

    function D:SyncFromDB()
        self.enabled = (DB and DB.debug) and true or false
        self.level = (DB and tonumber(DB.debugLevel)) or 2
        self.keep = (DB and tonumber(DB.debugKeep)) or 400
        if self.keep < 50 then self.keep = 50 end
        if self.keep > 2000 then self.keep = 2000 end
    end

    function D:Push(line)
        local keep = self.keep or 400
        self.head = (self.head % keep) + 1
        self.buf[self.head] = line
        if self.count < keep then
            self.count = self.count + 1
        end
    end

    function D:Log(level, category, msg)
        self:SyncFromDB()
        level = tonumber(level) or 2
        if not self.enabled then
            if level ~= 0 then return end
        else
            if level > (self.level or 2) then return end
        end

        local cat = tostring(category or "dbg")
        local line = NowStr() .. " [" .. cat .. "] " .. tostring(msg)
        self:Push(line)
        if IG._debugFrame and IG._debugFrame.IsShown and IG._debugFrame:IsShown() then
            self:ScheduleRefresh()
        end
    end

    function D:GetLines(n)
        self:SyncFromDB()
        local out = {}
        local cnt = self.count or 0
        if cnt <= 0 then return out end
        n = tonumber(n) or cnt
        if n > cnt then n = cnt end
        local keep = self.keep or 400
        local idx = self.head
        for i = 1, n do
            out[n - i + 1] = self.buf[idx]
            idx = idx - 1
            if idx <= 0 then idx = keep end
        end
        return out
    end

    function D:Clear()
        if wipe then
            wipe(self.buf)
        else
            for k in pairs(self.buf) do
                self.buf[k] = nil
            end
        end
        self.head = 0
        self.count = 0
    end

    local function EnsureDebugFrame()
        if IG._debugFrame then return IG._debugFrame end

        local f = CreateFrame("Frame", "InterruptGlowDebugFrame", UIParent, "BackdropTemplate")
        f:SetSize(700, 450)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 16,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            f:SetBackdropColor(0, 0, 0, 0.9)
        end

        local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("InterruptGlow Debug Log")

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)

        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -40)
        scroll:SetPoint("BOTTOMRIGHT", -30, 12)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(640)
        edit:SetAutoFocus(false)
        edit:EnableMouse(true)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)

        scroll:SetScrollChild(edit)

        f.edit = edit
        IG._debugFrame = f
        return f
    end

    function D:Show(n, noFocus)
        local f = EnsureDebugFrame()
        f._shownN = tonumber(n) or (self.keep or 400)
        local lines = self:GetLines(f._shownN)
        f.edit:SetText(table.concat(lines, "\n"))
        f:Show()
        f.edit:HighlightText(0)
        if not noFocus then
            f.edit:SetFocus()
        end
    end

    function D:RefreshShown()
        local f = IG._debugFrame
        if not f or not f.IsShown or not f:IsShown() then return end
        local n = f._shownN or (self.keep or 400)
        local lines = self:GetLines(n)
        f.edit:SetText(table.concat(lines, "\n"))
        f.edit:HighlightText(0)
    end

    function D:ScheduleRefresh()
        if self._refreshScheduled then return end
        self._refreshScheduled = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, function()
                self._refreshScheduled = false
                D:RefreshShown()
            end)
        else
            self._refreshScheduled = false
            D:RefreshShown()
        end
    end

    function D:DumpToChat(n)
        local lines = self:GetLines(n or 30)
        for i = 1, #lines do
            Print(lines[i])
        end
    end
end

IG._dbgStats = IG._dbgStats or {
    cd = {},
    ni = {},
    guard = {},
    slot = { ok = 0, bad = 0 },
    errors = 0,
}

function IG:StatInc(group, key)
    local stats = self._dbgStats
    if not stats then return end
    local bucket = stats[group]
    if type(bucket) ~= "table" then return end
    bucket[key] = (bucket[key] or 0) + 1
end

function IG:Dbg(level, category, msg)
    if self.Debug and self.Debug.Log then
        self.Debug:Log(level, category, msg)
    end
end
