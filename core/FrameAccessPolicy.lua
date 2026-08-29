local IG = _G.InterruptGlow
if not IG or not IG.Glow then return end

local Glow = IG.Glow
local _G = _G
local CreateFrame = _G.CreateFrame
local pcall = pcall
local type = type

local function MarkOverlayForbidden(record)
    record.overlayForbidden = true
    record.overlayPending = false
    record.overlayQueued = false
    Glow.prewarmQueued[record] = nil
end

local function CanCreateOnButton(button)
    if not IG.CanAccess(button) then return false end

    local method, memberKnown = IG:ReadMember(button, "IsForbidden")
    if not memberKnown then return false end
    if method == nil then return true end
    if type(method) ~= "function" then return false end

    local ok, forbidden = pcall(method, button)
    if not ok or not IG.CanAccess(forbidden) or type(forbidden) ~= "boolean" then
        return false
    end
    return forbidden == false
end

local function SafeFrameLevel(button)
    local method, memberKnown = IG:ReadMember(button, "GetFrameLevel")
    if not memberKnown or type(method) ~= "function" then return 1 end

    local ok, value = pcall(method, button)
    if ok and IG.CanAccess(value) and type(value) == "number" then
        return value
    end
    return 1
end

local function ConfigureGlowTexture(texture, gate)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", gate, "TOPLEFT", -10, 10)
    texture:SetPoint("BOTTOMRIGHT", gate, "BOTTOMRIGHT", 10, -10)
    texture:SetBlendMode("ADD")

    local atlasApplied = false
    if type(texture.SetAtlas) == "function" then
        atlasApplied = pcall(texture.SetAtlas, texture, "UI-HUD-RotationHelper-ProcAltGlow", false)
    end
    if not atlasApplied then
        texture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    end

    texture:SetVertexColor(1, 0.82, 0, 1)
    texture:SetAlpha(1)
    texture:Show()
end

local function CreateUnitBranch(button)
    local plainGate = CreateFrame("Frame", nil, button)
    plainGate:SetAllPoints(button)
    plainGate:SetFrameLevel(SafeFrameLevel(button) + 8)
    plainGate:SetAlpha(0)
    plainGate:Show()

    local niGate = plainGate:CreateTexture(nil, "OVERLAY", nil, 7)
    ConfigureGlowTexture(niGate, plainGate)

    return {
        plainGate = plainGate,
        niGate = niGate,
        candidate = false,
        animation = nil,
    }
end

-- Own the complete shell creation boundary. The previous implementation could
-- continue after IsForbidden errored or returned an inaccessible/non-boolean
-- value. Foreign frame access is now explicit fail-closed before any addon frame
-- or texture is allocated.
function Glow:CreateShell(record)
    if not record or not record.button then return nil end
    if record.overlay then return record.overlay end
    if record.overlayForbidden then return nil end
    if IG:IsInCombat() then
        record.overlayPending = true
        return nil
    end

    local button = record.button
    if not CanCreateOnButton(button) then
        MarkOverlayForbidden(record)
        IG:BumpStat("ui.shellsForbidden")
        return nil
    end

    record.overlay = {
        target = CreateUnitBranch(button),
        focus = CreateUnitBranch(button),
        cooldownText = nil,
        enhanced = false,
    }
    record.overlayPending = false
    record.overlayQueued = false
    self.prewarmQueued[record] = nil
    IG:BumpStat("ui.shellsCreated")
    return record.overlay
end

IG:RegisterModule("FrameAccessPolicy", {
    inaccessibleForeignFrameFailsClosed = true,
    forbiddenQueryMustReturnOrdinaryBoolean = true,
    ownsShellCreationBoundary = true,
})
