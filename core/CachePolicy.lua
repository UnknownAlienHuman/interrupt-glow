local IG = _G.InterruptGlow
if not IG or not IG.Buttons or not IG.Cooldown then return end

local Buttons = IG.Buttons
local Cooldown = IG.Cooldown
local pairs = pairs
local next = next

-- Dormant canonical abilities are deliberately retained during same-spec
-- conditional-macro churn. A real specialization change is the bounded cache
-- invalidator: after every button has been reconciled, unreferenced abilities
-- and old source-readiness entries can be discarded together.
function Buttons:PruneDormantAbilities()
    local removed = 0
    for key, ability in pairs(IG.AbilityStates) do
        if not ability or not ability.records or next(ability.records) == nil then
            IG.AbilityStates[key] = nil
            removed = removed + 1
        end
    end

    if removed > 0 then IG:BumpStat("abilities.pruned", removed) end
    return removed
end

function Cooldown:ResetCaches()
    if self.cache then
        if self.cache.action then IG:WipeMap(self.cache.action) end
        if self.cache.spell then IG:WipeMap(self.cache.spell) end
        if self.cache.pet then IG:WipeMap(self.cache.pet) end
    end
    if self.gcdHints then IG:WipeMap(self.gcdHints) end
    self.generation = 0
    IG:BumpStat("cooldown.cacheResets")
end
