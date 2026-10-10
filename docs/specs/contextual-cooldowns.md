# Contextual cooldowns and auras (the Context addon)

> Status: draft · Decided on 2026-10-10 by Finess: a NEW addon (Mage Kit's best parts may be pulled
> in later); first playable phase = mage cooldowns and procs. Name: Context (decided 2026-10-10 by Finess).

## The problem

On WoW: Forever the game hides most combat values from addons (secret values), and the combat log
is closed. Classic tools (WeakAuras-style "if mana < 30% and Frostbolt ready then glow") can't be
built the old way: Lua can't read the numbers it would compare. Blizzard's own Cooldown Manager
shows cooldowns and tracked auras correctly, but offers little customization (no conditions, no
custom glows, sounds limited to its alerts, fixed looks), and nothing learns from how you play.

A mage today can't, for example: get a glow + sound when Clearcasting procs while Arcane Missiles
is ready; see Ice Barrier's remaining time as a bar that turns red under 5 s; group their defensives
in one movable block; or find out after a fight that Evocation sat ready for 40 s while they were
out of mana.

## What we want

1. **Displays** you can place anywhere: icons, bars, texts, and **groups** of them (drag and drop,
   grow left/right/up/down, spacing). Every display shows a **source**: a spell's cooldown, an aura
   on a unit (you, target, focus, party, nameplates), an item, a weapon enchant, or a Blizzard
   Cooldown Manager item.
2. **Everything about the look is editable**, per display and per state: icon texture and crop,
   swipe (color, reverse, edge), the **spark** on bars, borders (style, size, color), glow (type,
   color, speed), fonts, cooldown timer text and duration text (format, position, color), bar
   texture and colors, background. **Shared media** (LibSharedMedia) for every font, texture,
   border and sound.
3. **Conditions** that change a display's look or fire actions, combinable with AND / OR / NOT, and
   **comparisons** wherever the value is comparable (remaining time, charges, stacks, range, health
   %, mana %, combat, group, zone, target type...).
4. **Honesty about hidden values**: every condition is labeled by HOW it's decided (see Decisions):
   either Lua decides it (usable anywhere, can play sounds and fire reminders), or only the ENGINE
   can (it can drive looks: show/hide, color, alpha; never a sound or a reminder). The editor shows
   which, and where (e.g. "visual only in instances").
5. **Actions** on a state change: glow, sound (shared media, text-to-speech), color change, show /
   hide, a screen message, a chat line (solo-safe, lockdown-safe).
6. **Range on cooldown icons**: an icon dims or tints when its spell is out of range of your target
   (engine-driven when the answer is hidden).
7. **Reminders**: out-of-combat checks with a message and an optional sound ("no Arcane
   Intellect", "no Mage Armor", "mana gem missing", "wand not equipped").
8. **Spell history**: a record of your fights (casts, procs, cooldown and aura edges, mana when
   readable, the game's damage meter totals after the fight), kept for N fights.
9. **Insights from history**: after a fight, plain-language findings, e.g. "Evocation was ready for
   40 s while you were under 30% mana", "Clearcasting procs: 6, used 4", "you spent 22% of the fight
   not casting", "Frostbolt rank 4 did 31% more damage per mana than rank 9 here". Each insight
   says what it's based on and how sure it is.
10. **Import / export** of displays and groups as a string.

## What we DON'T do

- **No combat-log features** (other players' casts, damage per spell from the log): the log can't
  be registered on Forever. Damage comes only from the game's damage meter, after combat.
- **No reading back the engine**: never infer a hidden value from what an engine widget shows
  (Blizzard blocks it on purpose).
- **No conditions the game hides turned into sounds or reminders**: hidden → visuals only.
- **No automation of gameplay** (no casting decided by the addon, no rotation bot): it shows and
  tells, the player acts. (Blizzard's own rotation helper may be shown if Forever enables it.)
- **No Mage Kit features at first**: Mage Kit keeps its windows; pulling its best parts in is a
  later decision.
- **No code or text taken from addons whose license forbids it** (see Links: addon lessons). Code
  from GPL-2.0(-or-later) and permissive (MIT, BSD, zlib) addons may be reused with its notice and
  credit kept; "all rights reserved" addons give ideas only; GPL-3.0-only code is not mixed in (it
  can't be combined with GPL-2.0-only code such as WeakAuras / EverAuras).

## Edge cases

- A condition whose value is hidden right now (combat, instance): the display keeps its last
  Lua-decided state, or falls to its engine-driven visual; never a wrong sound.
- A spell the character doesn't know (another rank, not trained): the display is hidden or shown
  greyed (per display setting), never an error.
- Ranks: displays track a spell by NAME (highest rank) unless pinned to a rank.
- Blizzard's Cooldown Manager switched off, or the spell not in it: the display uses our own
  sources; features that need its edges say so in the editor.
- A pooled Blizzard item that changes spell (see the hooking rules): re-resolved, never trusted
  across a release.
- Reload / login mid-fight: history marks the fight incomplete instead of guessing.
- 100+ displays: no per-frame work for displays off-screen or whose sources didn't change.
- Two displays for the same thing: allowed, independent.
- Import of a string from a newer version: refused with a message, never a half import.

## Decisions

- 2026-10-10, Finess: a new addon; Mage Kit's best parts may be pulled in later.
- 2026-10-10, Finess: phase 1 = mage cooldowns and procs, playable early.
- 2026-10-10: conditions are classified by the five ways to derive a conditional
  (`forever-techniques` section 0): A readable side channel, B the event itself, C geometry and
  time, D engine decides (visual only), E ask before reading. A/B/C/E can drive sounds and
  reminders; D only looks.
- 2026-10-10: displays are fed by OUR sources (duration objects, aura instance-ID lists, engine aura
  containers, cast events) first; Blizzard's Cooldown Manager is hooked for its engine edges
  (available, charge gained, aura applied/removed, pandemic, on cooldown) when the spell is in it,
  following the hooking rules (`forever-techniques/references/cooldown-manager.md`).
- 2026-10-10, Finess: Context's license is GPL-compatible: **GPL-2.0-or-later** (`LICENSE`,
  `## X-License` in the .toc). Why: EverAuras (a WeakAuras for Forever that works in combat, the
  closest existing design, `forever-techniques/references/everauras.md`) and WeakAuras are GPL-2.0;
  this lets Context reuse their Forever code with credit instead of re-implementing it.
- 2026-10-10, Finess: Context keeps its own design (this spec) and **borrows pieces** from the two
  WeakAuras forks for Forever, EverAuras and ForeverAuras (both GPL-2.0), with their notice and
  credit kept in the copied files: the geometry gates (missing, time left, stacks, total duration),
  animation-only glows, groups that follow secret sizes. Not a fork of either: Context stays smaller
  (mage cooldowns and procs first, Cooldown Manager edges, history, insights).
- 2026-10-10: history keeps only what the player did and what the game shows the player (own casts,
  own auras, own cooldowns, damage meter totals): no data about other players beyond what the game
  shows on screen.

## Acceptance criteria

Phase 1 (mage cooldowns and procs):
1. [human] A group of icons for Blink, Ice Block, Frost Nova, Counterspell, Evocation shows each
   cooldown's swipe and remaining time, in and out of combat, in a dungeon too. Known-good control:
   the same spells in Blizzard's Cooldown Manager. Observer: Finess, in game.
2. [human] An icon for Clearcasting (or another proc) appears with its duration when it procs and
   vanishes when consumed; with "glow + sound on appear" set, both happen once per proc.
   Control: the buff in the default buff frame.
3. [human] A bar for Ice Barrier counts down and turns red under 5 s (a Lua-decided condition when
   readable; when hidden, the editor marks it visual-only and it still turns red, engine-driven).
4. [human] The group is dragged in Edit Mode, grows in the chosen direction, and keeps its place
   after /reload.
5. [human] An out-of-range Counterspell icon dims on a far target, lights up in range.
6. [test] Condition evaluation (AND/OR/NOT, comparisons, the A-E classification) gives the expected
   state for a table of inputs, hidden inputs included. → tests/
7. [check] Lua 5.1, sizes, translations, tests. → /wow-addon-dev:check
8. [agent] No write onto Blizzard frames, hooks post-only and per frame, nothing protected created in
   combat. → api-gotcha-reviewer

Later phases get their own criteria when planned (history, insights, reminders, full editor,
import/export).

## Contract

- **Saved data**: `ContextDB` with `version`, `displays` (id → definition), `groups`, `history`
  (fights, capped). Every definition carries a `schema` number; migrations on login, never a silent
  drop.
- **Display definition** (stable fields): `id`, `type` (icon | bar | text), `schema`, `group` (a
  group id, or `pos` when standalone), `source` (`{ kind = "spell" | "aura" | "item" | "enchant" |
  "cdm", spell = id | name | { id, name }, unit, filter, slot }`), `visibility` (always |
  whenPresent | whenOnCooldown | whenReady), `look` (the base look, over the type's defaults),
  `states` (list of `{ name, when = <condition tree of { test, compare, value, way } and
  { op = "and" | "or" | "not", conditions }>, look = <what this state adds> }`, merged in order while
  the state holds), `actions` (phase 1 step 5). Groups: `{ id, name, grow, spacing, pos, children }`.
  (2026-10-10: `look` per state and `conditions` became `states`, one entry per state with its
  condition and its look.)
- **Import / export string**: `!Context:<schema>!` + Base64(compress(CBOR(definition))) using
  `C_EncodingUtil`; versioned, refused when newer.

## Links

- [`forever-techniques`](https://github.com/Arouid/wow-addon-workspace/tree/main/plugins/wow-addon-dev/skills/forever-techniques)
  (the five ways, engine timers, aura filters, secret sinks), in Finess's copy of the wow-addon-dev
  plugin
- Hooking rules: [`references/cooldown-manager.md`](https://github.com/Arouid/wow-addon-workspace/blob/main/plugins/wow-addon-dev/skills/forever-techniques/references/cooldown-manager.md)
- Engine aura containers: [`references/forevercoreskill.md`](https://github.com/Arouid/wow-addon-workspace/blob/main/plugins/wow-addon-dev/skills/forever-techniques/references/forevercoreskill.md);
  addon lessons (license-checked): [`references/addon-lessons.md`](https://github.com/Arouid/wow-addon-workspace/blob/main/plugins/wow-addon-dev/skills/forever-techniques/references/addon-lessons.md)
- ForeverAuras (GPL-2.0, reusable with credit): [`references/foreverauras.md`](https://github.com/Arouid/wow-addon-workspace/blob/main/plugins/wow-addon-dev/skills/forever-techniques/references/foreverauras.md)
- EverAuras (GPL-2.0, reusable with credit): [`references/everauras.md`](https://github.com/Arouid/wow-addon-workspace/blob/main/plugins/wow-addon-dev/skills/forever-techniques/references/everauras.md);
  geometry gates (NOT, time left, stacks) are in `forever-techniques` section 1
- Edit Mode placement (criterion 4): [LibEditMode](https://github.com/p3lim-wow/LibEditMode) (p3lim,
  `.toc` 16001, embeddable unmodified with its LICENSE.txt; TargetedSpells uses it) is the candidate
  library; notes in `references/addon-lessons.md`
- Mage Kit (Finess's other addon, private repo: source of measured facts and possible pulls): its
  `docs/verified-in-game.md` and `docs/range-measurement.md`

## Plan (2026-10-10, phase 1 only; one session per task)

1. Create the addon (`/wow-addon-dev:new-addon <Name>`, linked into the game), saved data with schema.
   → done 2026-10-10.
2. Sources: spell cooldown (duration object, charges, usable, range), aura (instance-ID filters +
   duration object), weapon enchant. Pure condition evaluator with the A-E classification + tests.
   → done 2026-10-10 (`Sources.lua`, `Conditions.lua`, `Probe.lua`, `tests/test_Context.lua`:
   criterion 6 passes headless). Every read answers in three values plus its way; an answer the
   predicates declared hidden (E) counts as hidden, so the condition goes visual-only (D). Not yet
   seen in game: `/context probe` is the first thing to try (see `docs/verified-in-game.md`).
3. Displays: icon (swipe, timer text, border, glow), bar (fill from duration, spark, timer text),
   group (grow direction, spacing), Edit Mode placement.
   → done 2026-10-10 except Blizzard's Edit Mode (`Looks.lua`, `Widgets.lua`, `Displays.lua`,
   `Groups.lua`, `Preset.lua`): swipes, bar fills and timer texts take duration objects (the engine
   counts); the "Ice Barrier under 5 s" state is also drawn engine-side through a color curve on the
   duration object (Grid2's technique) so it holds when the time is hidden; a state the evaluator
   can't decide keeps its last Lua-decided value; a proc glow comes from Blizzard's
   `ActionButtonSpellAlertTemplate` on a frame of ours. Placement is a plain drag (`/context edit`,
   out of combat, offsets saved from the screen center); LibEditMode (criterion 4 proper) waits for
   Finess's go on downloading the library. The "Mage essentials" preset of step 5 is already in
   (`/context preset mage`, installed on a mage's first login). Nothing seen in game yet.
4. Blizzard Cooldown Manager hooks (per-frame edges) as an optional source of state changes.
5. Actions: glow, sound (shared media, text-to-speech), color; a minimal editor to build the
   phase-1 mage set; a preset "Mage essentials".
6. In-game test pass against the acceptance criteria; then plan phase 2 (history and insights).
