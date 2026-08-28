# Interrupt IDs — WoW Retail 12.1.0.69497

## Ordinary specialization snapshot

```text
Gethe/wow-ui-source
commit: 027d26c3406d3de2cbd2b1f67d468fe033a1bcd4
file: Interface/AddOns/Blizzard_CooldownBroadcaster/TrackedCooldowns.lua
section: namespace.InterruptSpellsBySpec
```

`Blizzard_CooldownBroadcaster` is an internal LoadOnDemand MDI component. Interrupt Glow does **not** load or reference it at runtime. Its table is a reviewed build-time source for ordinary specialization interrupts, not an exhaustive PvP/direct-pet registry.

Slot-backed action buttons remain authoritative at runtime through `C_ActionBar.IsInterruptAction(slot)`. Static data is used for direct spell buttons, pet aliases and Cooldown Viewer identity.

| Class | Specialization | Spec ID | Ordinary interrupt IDs |
|---|---|---:|---|
| Death Knight | Blood | 250 | `47528` Mind Freeze |
| Death Knight | Frost | 251 | `47528` Mind Freeze |
| Death Knight | Unholy | 252 | `47528` Mind Freeze |
| Demon Hunter | Havoc | 577 | `183752` Disrupt |
| Demon Hunter | Vengeance | 581 | `183752` Disrupt |
| Demon Hunter | Devourer | 1480 | `183752` Disrupt |
| Druid | Balance | 102 | `78675` Solar Beam |
| Druid | Feral | 103 | `106839` Skull Bash |
| Druid | Guardian | 104 | `106839` Skull Bash |
| Evoker | Devastation | 1467 | `351338` Quell |
| Evoker | Augmentation | 1473 | `351338` Quell |
| Hunter | Beast Mastery | 253 | `147362` Counter Shot |
| Hunter | Marksmanship | 254 | `147362` Counter Shot |
| Hunter | Survival | 255 | `187707` Muzzle |
| Mage | Arcane | 62 | `2139` Counterspell |
| Mage | Fire | 63 | `2139` Counterspell |
| Mage | Frost | 64 | `2139` Counterspell |
| Monk | Brewmaster | 268 | `116705` Spear Hand Strike |
| Monk | Windwalker | 269 | `116705` Spear Hand Strike |
| Paladin | Protection | 66 | `96231` Rebuke |
| Paladin | Retribution | 70 | `96231` Rebuke |
| Priest | Shadow | 258 | `15487` Silence |
| Rogue | Assassination | 259 | `1766` Kick |
| Rogue | Outlaw | 260 | `1766` Kick |
| Rogue | Subtlety | 261 | `1766` Kick |
| Shaman | Elemental | 262 | `57994` Wind Shear |
| Shaman | Enhancement | 263 | `57994` Wind Shear |
| Shaman | Restoration | 264 | `57994` Wind Shear |
| Warlock | Affliction | 265 | `119910` Command Demon Spell Lock, `132409` Grimoire of Sacrifice Spell Lock |
| Warlock | Demonology | 266 | `119910` Command Demon Spell Lock, `119914` Command Demon Axe Toss |
| Warlock | Destruction | 267 | `119910` Command Demon Spell Lock, `132409` Grimoire of Sacrifice Spell Lock |
| Warrior | Arms | 71 | `6552` Pummel |
| Warrior | Fury | 72 | `6552` Pummel |
| Warrior | Protection | 73 | `6552` Pummel, `386071` Disrupting Shout |

## Reviewed exceptions outside the MDI snapshot

| Specs | ID | Ability | Reason |
|---|---:|---|---|
| Warlock 265/266/267 | `212619` | Call Felhunter | PvP-talent interrupt absent from the MDI-oriented table |

Every exception is still gated by `C_SpellBook.IsSpellKnownOrInSpellBook`. Talent/PvP invalidation listens to active combat config, talent group, trait config, PvP talent and `SPELLS_CHANGED`.

## Specializations absent from the ordinary snapshot

The Blizzard table does not list an ordinary interrupt for Restoration Druid, Preservation Evoker, Mistweaver Monk, Holy Paladin, Discipline Priest or Holy Priest. Interrupt Glow does not statically assume class-wide availability. If Blizzard classifies a current slot as an interrupt, its spell family may be learned for the current specialization/session.

## Pet-action aliases

Accepted only from actual pet-action sources:

| Pet action | Canonical player family |
|---:|---:|
| `19647` Felhunter Spell Lock | `119910` Command Demon Spell Lock |
| `89766` Felguard Axe Toss | `119914` Command Demon Axe Toss |

`115781` Optical Blast is not in current Retail runtime data.

## Update procedure

```bash
python tools/sync_interrupts.py \
  --source ../wow-ui-source/Interface/AddOns/Blizzard_CooldownBroadcaster/TrackedCooldowns.lua \
  --data-file core/Data.lua \
  --check
```

After reviewing a build change, use `--write`, then update build metadata and live-test every changed specialization, PvP exception and pet mapping. The generated block must not overwrite `EXTRA_INTERRUPTS_BY_SPEC` or `PET_ACTION_ALIASES`.

## Readiness note

Interrupt identity and readiness are separate. A correct interrupt ID does not make a button ready. Final readiness also requires ignore-GCD duration, charges, usability, pet state and Loss of Control. `isOnGCD=true` is never accepted as positive readiness proof.
