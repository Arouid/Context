# Changelog

## Unreleased

- Displays: icons (swipe, timer text, stacks, border, proc glow, out-of-range tint) and bars (fill,
  spark, name, timer text) fed with duration objects so the engine keeps counting when the numbers
  are hidden; states (a condition tree plus the look it adds) merged over a base look; a "remaining
  under X seconds" color state also drawn by the engine through a color curve; groups growing
  left, right, up or down with spacing; groups and standalone displays dragged in Blizzard's Edit
  Mode (through LibEditMode), their place kept across reloads; `/context edit` as the plain drag
  when the library isn't loaded; `/context list`, `/context reset`.
- "Mage essentials" preset (`/context preset mage`, installed on a mage's first login with no
  displays): Blink, Ice Block, Frost Nova, Counterspell and Evocation cooldown icons in a group,
  the Clearcasting proc icon with a glow, the Ice Barrier bar turning red under 5 s.
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
