local IG = _G.InterruptGlow
if not IG or not IG.Buttons then return end

local Buttons = IG.Buttons
local _G = _G
local C_AddOns = _G.C_AddOns
local C_Timer = _G.C_Timer
local hooksecurefunc = _G.hooksecurefunc
local pcall = pcall
local type = type

local libraryHookInstalled = false
local loadHookInstalled = false
local discoveryScheduled = false

local function IsLABLibraryName(name)
    return type(name) == "string" and name:match("^LibActionButton%-1%.0") ~= nil
end

local function RunDiscovery()
    discoveryScheduled = false
    if Buttons.attached then
        Buttons:AttachLAB(IG.playerLoginSeen == true, false)
    end
end

local function ScheduleDiscovery()
    if discoveryScheduled or not Buttons.attached then return end
    discoveryScheduled = true

    -- LibStub:NewLibrary returns before the provider populates the new table.
    -- Defer one turn so RegisterCallback and the provider registry exist.
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, RunDiscovery)
    else
        RunDiscovery()
    end
end

local function OnLibraryRegistered(_, major)
    if IsLABLibraryName(major) then ScheduleDiscovery() end
end

local function InstallLibraryHook()
    if libraryHookInstalled then return true end

    local LibStub = _G.LibStub
    if not LibStub
        or type(LibStub.NewLibrary) ~= "function"
        or type(hooksecurefunc) ~= "function"
    then
        return false
    end

    local ok = pcall(hooksecurefunc, LibStub, "NewLibrary", OnLibraryRegistered)
    if not ok then return false end
    libraryHookInstalled = true
    return true
end

local function OnAddOnLoaded()
    -- A LoadOnDemand provider may introduce LibStub and its LAB library in the
    -- same load transaction. The post-hook runs after that transaction, so scan
    -- the registry once and install the library-registration hook for later loads.
    InstallLibraryHook()
    ScheduleDiscovery()
end

local function InstallLoadHook()
    if loadHookInstalled then return true end
    if not C_AddOns
        or type(C_AddOns.LoadAddOn) ~= "function"
        or type(hooksecurefunc) ~= "function"
    then
        return false
    end

    local ok = pcall(hooksecurefunc, C_AddOns, "LoadAddOn", OnAddOnLoaded)
    if not ok then return false end
    loadHookInstalled = true
    return true
end

local function InstallHooks()
    InstallLibraryHook()
    InstallLoadHook()
end

local originalAttach = Buttons.Attach
function Buttons:Attach(discoverExisting)
    InstallHooks()
    originalAttach(self, discoverExisting)
    -- LibStub may have appeared while another integration attached.
    InstallLibraryHook()
end

local originalDiscoverAll = Buttons.DiscoverAll
function Buttons:DiscoverAll(force)
    InstallHooks()
    return originalDiscoverAll(self, force)
end

IG:RegisterModule("LABRegistrationPolicy", {
    providerNeutral = true,
    hooksLibraryRegistration = true,
    hooksLoadOnDemandCompletion = true,
    usesGenericAddOnLoadedEvent = false,
    pollsProviders = false,
})
