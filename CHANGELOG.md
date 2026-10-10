# Changelog

## Unreleased

- Sources: spell cooldowns (never-secret isActive / isEnabled / isOnGCD, remaining time when plain,
  duration objects for widgets), charges, usable, range (the SPELL_RANGE_CHECK_UPDATE event first,
  IsSpellInRange as fallback), auras on a unit (by spell ID after asking C_Secrets, by name only
  while auras aren't restricted, index walks only where the per-index predicate says plain), weapon
  enchants. Every read answers true / false / can't say, tagged by the way it was decided (A-E).
- The pure condition evaluator: AND / OR / NOT, comparisons on plain values, hidden inputs make a
  condition visual-only instead of a boolean.
- `/context probe [spell]`: prints what the sources answer for a spell's cooldown and the matching
  aura on you (default: Frost Nova and Clearcasting), to try in and out of combat.

## v0.1.0 - 2026-10-10

- First version: the `/context` command and the `ContextDB` saved variables, in English, French,
  German and Spanish.
