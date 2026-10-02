local ROOT = arg[1] or "."
_G = _G or _ENV

local unpackValues = table.unpack or unpack
local queued = {}
local loadCalls = 0
local attachLABCalls = 0

C_Timer = {
    After = function(delay, callback)
        assert(delay == 0)
        queued[#queued + 1] = callback
    end,
}

C_AddOns = {
    LoadAddOn = function(name)
        loadCalls = loadCalls + 1
        return name
    end,
}

function hooksecurefunc(target, methodName, hook)
    local original = assert(target[methodName], "missing hook target: " .. tostring(methodName))
    target[methodName] = function(...)
        local results = { original(...) }
        hook(...)
        return unpackValues(results)
    end
end

local Buttons = {
    attached = false,
}

function Buttons:Attach()
    self.attached = true
end

function Buttons:DiscoverAll()
    return true
end

function Buttons:AttachLAB(discoverExisting, force)
    attachLABCalls = attachLABCalls + 1
    assert(discoverExisting == true)
    assert(force == false)
end

InterruptGlow = {
    Buttons = Buttons,
    playerLoginSeen = true,
}

function InterruptGlow:RegisterModule(name, module)
    self.registeredName = name
    self.registeredModule = module
end

LibStub = {
    NewLibrary = function(self, major, minor)
        self.lastMajor = major
        self.lastMinor = minor
        return {}
    end,
}

local loader, loadError = loadfile(ROOT .. "/core/LABRegistrationPolicy.lua")
assert(loader, loadError)
loader()

Buttons:Attach(true)
assert(Buttons.attached == true)

LibStub:NewLibrary("OtherLibrary-1.0", 1)
assert(#queued == 0, "unrelated library scheduled LAB discovery")

LibStub:NewLibrary("LibActionButton-1.0-ProviderFork", 2)
assert(#queued == 1, "LAB registration did not schedule discovery")
queued[1]()
assert(attachLABCalls == 1, "scheduled LAB discovery did not run")

-- Hook installation is idempotent. Calling manual discovery must not stack a
-- second NewLibrary post-hook.
Buttons:DiscoverAll(true)
LibStub:NewLibrary("LibActionButton-1.0-SecondProvider", 3)
assert(#queued == 2, "LAB registration was scheduled more or less than once")
queued[2]()
assert(attachLABCalls == 2)

C_AddOns.LoadAddOn("AnyLoadOnDemandProvider")
assert(loadCalls == 1)
assert(#queued == 3, "LoadOnDemand completion did not schedule one bounded rescan")
queued[3]()
assert(attachLABCalls == 3)

Buttons.attached = false
LibStub:NewLibrary("LibActionButton-1.0-DetachedProvider", 4)
assert(#queued == 3, "detached integration scheduled discovery")

assert(InterruptGlow.registeredName == "LABRegistrationPolicy")
assert(InterruptGlow.registeredModule.providerNeutral == true)
assert(InterruptGlow.registeredModule.pollsProviders == false)
assert(InterruptGlow.registeredModule.usesGenericAddOnLoadedEvent == false)

print("LAB REGISTRATION POLICY TEST PASSED")
