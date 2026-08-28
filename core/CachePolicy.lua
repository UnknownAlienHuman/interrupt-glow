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
        if not ability or next(ability.records) == nil then
            IG.AbilityStates[key] = nil
            removed = removed + 1
        end
    end

    if removed > 0 then IG:BumpStat("abilities.pruned", removed) end
    return removed
end

function Cooldown:ResetCaches()
    IG:WipeMap(self.cache.action)
    IG:WipeMap(self.cache.spell)
    IG:WipeMap(self.cache.pet)
    IG:WipeMap(self.gcdHints)
    self.generation = 0
    IG:BumpStat("cooldown.cacheResets")
end
