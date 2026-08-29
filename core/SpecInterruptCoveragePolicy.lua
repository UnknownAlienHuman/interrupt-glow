local IG = _G.InterruptGlow
if not IG or not IG.Data then return end

local Data = IG.Data
local _G = _G
local type = type
local pcall = pcall

-- Blizzard_CooldownBroadcaster's MDI snapshot is the ordinary baseline, but it
-- intentionally does not enumerate every optional class-tree interrupt for every
-- specialization. Direct spell, ButtonForge and Cooldown Viewer buttons do not
-- always pass through a slot-backed C_ActionBar.IsInterruptAction proof first.
-- Optional families therefore require an exact current spellbook proof; missing,
-- erroring or inaccessible spellbook APIs are not treated as implicit knowledge.
local OPTIONAL_INTERRUPTS_BY_SPEC = {
    [102] = { 106839 }, -- Balance Druid: optional Skull Bash
    [105] = { 106839 }, -- Restoration Druid: optional Skull Bash
    [1468] = { 351338 }, -- Preservation Evoker: Quell
    [270] = { 116705 }, -- Mistweaver Monk: Spear Hand Strike
    [65] = { 96231 }, -- Holy Paladin: Rebuke
}

local function AppendUnique(target, spellID)
    if type(target) ~= "table" or type(spellID) ~= "number" then return false end
    for index = 1, #target do
        if target[index] == spellID then return false end
    end
    target[#target + 1] = spellID
    return true
end

Data.exactKnownInterrupts = Data.exactKnownInterrupts or {}

local added = 0
for specID, additions in pairs(OPTIONAL_INTERRUPTS_BY_SPEC) do
    local target = Data.extraInterruptsBySpec[specID]
    if type(target) ~= "table" then
        target = {}
        Data.extraInterruptsBySpec[specID] = target
    end

    for index = 1, #additions do
        local spellID = additions[index]
        Data.exactKnownInterrupts[spellID] = true
        if AppendUnique(target, spellID) then added = added + 1 end
    end
end

function Data:RequiresExactKnownSpell(spellID)
    if not IG.CanAccess(spellID) or type(spellID) ~= "number" then return false end

    local spellBook = _G.C_SpellBook
    local predicate = spellBook and spellBook.IsSpellKnownOrInSpellBook
    if type(predicate) ~= "function" then return false end

    local ok, known = pcall(predicate, spellID)
    return ok and IG.CanAccess(known) and known == true
end

local originalRefreshActiveSpec = Data.RefreshActiveSpec
if type(originalRefreshActiveSpec) == "function" then
    function Data:RefreshActiveSpec(...)
        local specID, changed = originalRefreshActiveSpec(self, ...)
        local optional = OPTIONAL_INTERRUPTS_BY_SPEC[specID]

        if type(optional) == "table" then
            for index = 1, #optional do
                local spellID = optional[index]
                if not self:RequiresExactKnownSpell(spellID) then
                    -- The base data layer intentionally has a compatibility
                    -- fallback when C_SpellBook is absent. Optional talents must
                    -- not inherit that fail-open behavior.
                    self.specInterrupts[spellID] = nil
                    self.activeInterrupts[spellID] = nil
                end
            end
        end
        return specID, changed
    end
end

IG:RegisterModule("SpecInterruptCoveragePolicy", {
    optionalInterruptsBySpec = OPTIONAL_INTERRUPTS_BY_SPEC,
    addedEntries = added,
    spellbookGated = true,
    requiresExactKnownSpell = true,
    neverAddsUnknownOptionalInterrupts = true,
})
