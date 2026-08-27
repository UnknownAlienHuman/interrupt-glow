local IG = _G.InterruptGlow
if not IG then return end

local Data = {
    wowBuild = 69497,
    interface = 120100,
    sourceCommit = "027d26c3406d3de2cbd2b1f67d468fe033a1bcd4",
    activeSpecID = nil,
    specInterrupts = {},
    activeInterrupts = {},
    runtimeInterrupts = {},
    cooldownSpellMatchCache = {},
    interruptCooldownCategories = {},
    interruptStartRecoveryCategories = {},
}
IG.Data = Data
IG:RegisterModule("Data", Data)

-- Build-time source for ordinary player interrupts:
-- Blizzard_CooldownBroadcaster/TrackedCooldowns.lua,
-- namespace.InterruptSpellsBySpec, build 12.1.0.69497.
--
-- Blizzard_CooldownBroadcaster is an internal LoadOnDemand MDI component. It is
-- never loaded or referenced at runtime by Interrupt Glow; this is a vendored,
-- reviewed snapshot. It is not assumed to include PvP talents or direct pet
-- actions, which are maintained separately below.
-- BEGIN GENERATED INTERRUPTS_BY_SPEC
local INTERRUPTS_BY_SPEC = {
    [250] = { 47528 },                  -- Blood DK: Mind Freeze
    [251] = { 47528 },                  -- Frost DK: Mind Freeze
    [252] = { 47528 },                  -- Unholy DK: Mind Freeze
    [577] = { 183752 },                 -- Havoc DH: Disrupt
    [581] = { 183752 },                 -- Vengeance DH: Disrupt
    [1480] = { 183752 },                -- Devourer DH: Disrupt
    [102] = { 78675 },                  -- Balance Druid: Solar Beam
    [103] = { 106839 },                 -- Feral Druid: Skull Bash
    [104] = { 106839 },                 -- Guardian Druid: Skull Bash
    [1467] = { 351338 },                -- Devastation Evoker: Quell
    [1473] = { 351338 },                -- Augmentation Evoker: Quell
    [253] = { 147362 },                 -- Beast Mastery Hunter: Counter Shot
    [254] = { 147362 },                 -- Marksmanship Hunter: Counter Shot
    [255] = { 187707 },                 -- Survival Hunter: Muzzle
    [62] = { 2139 },                    -- Arcane Mage: Counterspell
    [63] = { 2139 },                    -- Fire Mage: Counterspell
    [64] = { 2139 },                    -- Frost Mage: Counterspell
    [268] = { 116705 },                 -- Brewmaster Monk: Spear Hand Strike
    [269] = { 116705 },                 -- Windwalker Monk: Spear Hand Strike
    [66] = { 96231 },                   -- Protection Paladin: Rebuke
    [70] = { 96231 },                   -- Retribution Paladin: Rebuke
    [258] = { 15487 },                  -- Shadow Priest: Silence
    [259] = { 1766 },                   -- Assassination Rogue: Kick
    [260] = { 1766 },                   -- Outlaw Rogue: Kick
    [261] = { 1766 },                   -- Subtlety Rogue: Kick
    [262] = { 57994 },                  -- Elemental Shaman: Wind Shear
    [263] = { 57994 },                  -- Enhancement Shaman: Wind Shear
    [264] = { 57994 },                  -- Restoration Shaman: Wind Shear
    [265] = { 119910, 132409 },         -- Affliction Warlock: Command Demon / Sacrifice
    [266] = { 119910, 119914 },         -- Demonology Warlock: Spell Lock / Axe Toss
    [267] = { 119910, 132409 },         -- Destruction Warlock: Command Demon / Sacrifice
    [71] = { 6552 },                    -- Arms Warrior: Pummel
    [72] = { 6552 },                    -- Fury Warrior: Pummel
    [73] = { 6552, 386071 },            -- Protection Warrior: Pummel, Disrupting Shout
}
-- END GENERATED INTERRUPTS_BY_SPEC

-- Verified interrupts not covered by Blizzard's MDI-oriented spec snapshot.
-- Keep these outside the generated block so an upstream sync cannot silently
-- delete them. IsSpellKnownOrInSpellBook still gates each entry at runtime.
local EXTRA_INTERRUPTS_BY_SPEC = {
    [265] = { 212619 },                 -- Affliction: Call Felhunter (PvP talent)
    [266] = { 212619 },                 -- Demonology: Call Felhunter (PvP talent)
    [267] = { 212619 },                 -- Destruction: Call Felhunter (PvP talent)
}

-- Pet action IDs are not present in Blizzard's player-spec broadcaster list.
-- They are accepted only when the source is an actual pet-action button and
-- only when their canonical Command Demon spell belongs to the current spec.
local PET_ACTION_ALIASES = {
    [19647] = 119910,   -- Felhunter Spell Lock -> Command Demon Spell Lock
    [89766] = 119914,   -- Felguard Axe Toss -> Command Demon Axe Toss
}

Data.interruptsBySpec = INTERRUPTS_BY_SPEC
Data.extraInterruptsBySpec = EXTRA_INTERRUPTS_BY_SPEC
Data.petActionAliases = PET_ACTION_ALIASES

local _G = _G
local C_SpellBook = _G.C_SpellBook
local C_SpecializationInfo = _G.C_SpecializationInfo
local PlayerUtil = _G.PlayerUtil
local Constants = _G.Constants
local GetSpecialization = _G.GetSpecialization
local GetSpecializationInfo = _G.GetSpecializationInfo
local pcall = pcall
local type = type
local pairs = pairs

local GLOBAL_RECOVERY_CATEGORY = Constants
    and Constants.SpellCooldownConsts
    and Constants.SpellCooldownConsts.GLOBAL_RECOVERY_CATEGORY
    or 133

local function SafeNumberCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or not IG.CanAccess(value) or type(value) ~= "number" then
        return nil
    end
    return value
end

local function GetCurrentSpecID()
    if PlayerUtil and type(PlayerUtil.GetCurrentSpecID) == "function" then
        local specID = SafeNumberCall(PlayerUtil.GetCurrentSpecID)
        if specID then return specID end
    end

    if C_SpecializationInfo and type(C_SpecializationInfo.GetSpecialization) == "function" then
        local specializationIndex = SafeNumberCall(C_SpecializationInfo.GetSpecialization)
        if specializationIndex and type(C_SpecializationInfo.GetSpecializationInfo) == "function" then
            local specID = SafeNumberCall(C_SpecializationInfo.GetSpecializationInfo, specializationIndex)
            if specID then return specID end
        end
    end

    local specializationIndex = SafeNumberCall(GetSpecialization)
    if not specializationIndex then return nil end
    return SafeNumberCall(GetSpecializationInfo, specializationIndex)
end

local function IsKnownOrInSpellBook(spellID)
    if not C_SpellBook or type(C_SpellBook.IsSpellKnownOrInSpellBook) ~= "function" then
        return true
    end

    local ok, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellID)
    return ok and IG.CanAccess(known) and known == true
end

local function FindBaseSpell(spellID)
    if not C_SpellBook or type(C_SpellBook.FindBaseSpellByID) ~= "function" then
        return nil
    end
    return SafeNumberCall(C_SpellBook.FindBaseSpellByID, spellID)
end

local function FindOverrideSpell(spellID)
    if not C_SpellBook or type(C_SpellBook.FindSpellOverrideByID) ~= "function" then
        return nil
    end
    return SafeNumberCall(C_SpellBook.FindSpellOverrideByID, spellID)
end

local function AddSpecList(self, list)
    if type(list) ~= "table" then return end
    for index = 1, #list do
        local spellID = list[index]
        self.specInterrupts[spellID] = true
        if IsKnownOrInSpellBook(spellID) then
            self.activeInterrupts[spellID] = true
        end
    end
end

local function IsRuntimeRelevant()
    local glow = IG.Glow
    if glow and type(glow.HasRelevantCast) == "function" and glow:HasRelevantCast() then
        return true
    end
    return IG.DB and IG.DB.enabled == true and IG.DB.cdText == true
end

function Data:RefreshActiveSpec()
    local specID = GetCurrentSpecID()
    local changed = specID ~= self.activeSpecID
    self.activeSpecID = specID

    IG:WipeMap(self.specInterrupts)
    IG:WipeMap(self.activeInterrupts)
    IG:WipeMap(self.cooldownSpellMatchCache)
    IG:WipeMap(self.interruptCooldownCategories)
    IG:WipeMap(self.interruptStartRecoveryCategories)

    if changed then
        -- Runtime discoveries are authoritative only inside the specialization
        -- that exposed them through C_ActionBar.IsInterruptAction. Preserve them
        -- across same-spec SPELLS_CHANGED bursts to avoid order-dependent CDM
        -- unbinds, but never carry them into another specialization.
        IG:WipeMap(self.runtimeInterrupts)
    end

    if specID then
        AddSpecList(self, INTERRUPTS_BY_SPEC[specID])
        AddSpecList(self, EXTRA_INTERRUPTS_BY_SPEC[specID])
    end

    IG:BumpStat("data.specRefreshes")
    return specID, changed
end

-- C_ActionBar.IsInterruptAction is authoritative for slot-backed actions. If a
-- future patch introduces an interrupt before the vendored tables are updated,
-- learn its spell family for the current session so CDM/custom copies can bind.
function Data:LearnRuntimeInterrupt(spellID)
    if not IG.CanAccess(spellID) or type(spellID) ~= "number" then
        return nil
    end

    local canonicalSpellID = FindBaseSpell(spellID) or spellID
    self.runtimeInterrupts[spellID] = canonicalSpellID
    self.runtimeInterrupts[canonicalSpellID] = canonicalSpellID
    self.cooldownSpellMatchCache[spellID] = true
    self.cooldownSpellMatchCache[canonicalSpellID] = true

    local overrideSpellID = FindOverrideSpell(canonicalSpellID)
    if overrideSpellID then
        self.runtimeInterrupts[overrideSpellID] = canonicalSpellID
        self.cooldownSpellMatchCache[overrideSpellID] = true
    end

    IG:BumpStat("data.runtimeInterruptsLearned")
    return canonicalSpellID
end

-- Returns the canonical cooldown identity or nil. Slot-backed buttons do not
-- depend on this table for classification; it is used for direct spell, pet and
-- Cooldown Viewer buttons.
function Data:GetCanonicalSpellID(spellID, sourceKind)
    if not IG.CanAccess(spellID) or type(spellID) ~= "number" then
        return nil
    end

    if sourceKind == "pet" then
        local alias = PET_ACTION_ALIASES[spellID]
        if alias and self.specInterrupts[alias] then
            return alias
        end
    end

    if self.activeInterrupts[spellID] then
        return spellID
    end

    local runtimeCanonical = self.runtimeInterrupts[spellID]
    if runtimeCanonical and IsKnownOrInSpellBook(runtimeCanonical) then
        return runtimeCanonical
    end

    local baseSpellID = FindBaseSpell(spellID)
    if baseSpellID then
        if self.activeInterrupts[baseSpellID] then
            return baseSpellID
        end
        runtimeCanonical = self.runtimeInterrupts[baseSpellID]
        if runtimeCanonical and IsKnownOrInSpellBook(runtimeCanonical) then return runtimeCanonical end
    end

    local overrideSpellID = FindOverrideSpell(spellID)
    if overrideSpellID then
        if self.activeInterrupts[overrideSpellID] then
            return overrideSpellID
        end
        runtimeCanonical = self.runtimeInterrupts[overrideSpellID]
        if runtimeCanonical and IsKnownOrInSpellBook(runtimeCanonical) then return runtimeCanonical end
    end

    return nil
end

function Data:IsInterruptSpell(spellID, sourceKind)
    return self:GetCanonicalSpellID(spellID, sourceKind) ~= nil
end

function Data:MatchesCurrentInterrupt(spellID)
    if not IG.CanAccess(spellID) or type(spellID) ~= "number" then
        return false
    end

    local cached = self.cooldownSpellMatchCache[spellID]
    if cached ~= nil then return cached end

    local matches = self.activeInterrupts[spellID] ~= nil
        or self.runtimeInterrupts[spellID] ~= nil
        or self:GetCanonicalSpellID(spellID, "spell") ~= nil
    self.cooldownSpellMatchCache[spellID] = matches
    return matches
end

function Data:LearnInterruptCooldownCategories(category, startRecoveryCategory)
    if IG.CanAccess(category)
        and type(category) == "number"
        and category ~= GLOBAL_RECOVERY_CATEGORY
    then
        self.interruptCooldownCategories[category] = true
    end
    if IG.CanAccess(startRecoveryCategory)
        and type(startRecoveryCategory) == "number"
        and startRecoveryCategory ~= GLOBAL_RECOVERY_CATEGORY
    then
        self.interruptStartRecoveryCategories[startRecoveryCategory] = true
    end
end

-- SPELL_UPDATE_COOLDOWN in 12.1 supplies the changed spell plus separate
-- cooldown and start-recovery categories. Exact interrupt events teach the
-- non-global categories used by that interrupt. Unknown non-global shared-
-- category events are checked only while the result can affect visible output;
-- unrelated global-recovery events are discarded because duration queries
-- already ignore the GCD.
function Data:ShouldRefreshForCooldownEvent(spellID, baseSpellID, category, startRecoveryCategory)
    if not IG.CanAccess(spellID)
        or not IG.CanAccess(baseSpellID)
        or not IG.CanAccess(category)
        or not IG.CanAccess(startRecoveryCategory)
    then
        return true
    end

    if spellID == nil then return true end

    if self:MatchesCurrentInterrupt(spellID) or self:MatchesCurrentInterrupt(baseSpellID) then
        self:LearnInterruptCooldownCategories(category, startRecoveryCategory)
        return true
    end

    if type(category) == "number" and self.interruptCooldownCategories[category] then
        return true
    end
    if type(startRecoveryCategory) == "number"
        and self.interruptStartRecoveryCategories[startRecoveryCategory]
    then
        return true
    end

    local hasNonGlobalCategory = type(category) == "number" and category ~= GLOBAL_RECOVERY_CATEGORY
        or (type(startRecoveryCategory) == "number" and startRecoveryCategory ~= GLOBAL_RECOVERY_CATEGORY)
    if hasNonGlobalCategory then
        return IsRuntimeRelevant()
    end

    return false
end

function Data:GetActiveInterrupts()
    return pairs(self.activeInterrupts)
end
