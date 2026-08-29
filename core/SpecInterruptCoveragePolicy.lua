local IG = _G.InterruptGlow
if not IG or not IG.Data then return end

local Data = IG.Data
local type = type

-- Blizzard_CooldownBroadcaster's MDI snapshot is the ordinary baseline, but it
-- intentionally does not enumerate every optional class-tree interrupt for every
-- specialization. Direct spell, ButtonForge and Cooldown Viewer buttons do not
-- always pass through a slot-backed C_ActionBar.IsInterruptAction proof first.
-- Add the known optional families here; Data:RefreshActiveSpec still admits each
-- spell only when C_SpellBook.IsSpellKnownOrInSpellBook reports it for the
-- current character/spec, so an unavailable talent cannot become a false button.
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

local added = 0
for specID, additions in pairs(OPTIONAL_INTERRUPTS_BY_SPEC) do
    local target = Data.extraInterruptsBySpec[specID]
    if type(target) ~= "table" then
        target = {}
        Data.extraInterruptsBySpec[specID] = target
    end

    for index = 1, #additions do
        if AppendUnique(target, additions[index]) then added = added + 1 end
    end
end

IG:RegisterModule("SpecInterruptCoveragePolicy", {
    optionalInterruptsBySpec = OPTIONAL_INTERRUPTS_BY_SPEC,
    addedEntries = added,
    spellbookGated = true,
})
