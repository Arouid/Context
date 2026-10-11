-- TestGuideSteps.lua: the in-game test guide's steps, one entry per row of the "Test guide" tables
-- in docs/verified-in-game.md, same IDs, same order (the headless test checks both lists match).
-- Entry: { id, title, step, step, ..., expect = what you should see, control = the known-good
-- comparison, wrong = how to read a wrong outcome, act = the guide's buttons (keys of
-- TestGuide.lua's ACTIONS, four at most), crit = the spec's acceptance criterion it covers }.
-- Groups by the ID's letter: T anywhere out of combat, F near mobs in the open world, D in a
-- dungeon. TestGuide.lua shows them. English only on purpose: a testing tool, not a player feature.
-- SPDX-License-Identifier: GPL-2.0-or-later (see LICENSE and README.md)
local _, ns = ...

ns.TEST_STEPS = {}
local function S(step) ns.TEST_STEPS[#ns.TEST_STEPS + 1] = step end

-- T. Anywhere, out of combat ----------------------------------------------------------------------
S{ "T0", "Preset on first login", act = { "reset", "reload", "list", "preset" },
    "This needs a mage with no Context data. On your first login it already happened; to see it again press Reset displays below, then Reload UI.",
    "After the reload, look below the screen center without typing anything.",
    "Press List displays below (or type /context list).",
    expect = "A row of five bright icons (Blink, Ice Block, Frost Nova, Counterspell, Evocation) below the screen center, no swipe. List displays says \"displays: 7, groups: 1\", names mage.blink to mage.evocation \"shown, 36 x 36, on screen\", mage.clearcasting and mage.icebarrier \"hidden\" (no proc, no barrier up), and ends with \"group mage.cooldowns: 196 x 36, on screen\".",
    control = "Press Preset mage below: it installs the same set by hand, and the list must read the same.",
    wrong = "Nothing on screen and \"displays: 0\" = the auto-install didn't run: not a mage, or ContextDB.presetInstalled was already set (Reset displays clears it, then Reload UI). Icons with a question mark = the spell's texture couldn't be read (not trained yet: note which). 7 listed but not the row of five = read the facts after each name: \"no size\" = the look never reached the frame, \"not anchored\" = it has no place, \"off screen\" = its saved position was beyond the screen (type /context why <id> for the full facts: anchor, parent, center, screen size); one icon instead of five = the group laid them out before they had a size (seen 2026-10-10; the row now lays out again after the first refresh)." }
S{ "T1", "Edit Mode placement (spec criterion 4)", crit = 4, act = { "edit", "why", "reload" },
    "Out of combat: Esc > Edit Mode. Drag the box labeled \"Mage cooldowns\" somewhere else, then the \"Clearcasting\" and \"Ice Barrier\" boxes.",
    "Leave Edit Mode (Done or Esc). Press Why below: one line per group and display with its size and whether it is on screen, the group's saved pos.",
    "Press Reload UI below (or type /reload), then open Edit Mode once more.",
    expect = "In Edit Mode each of the three shows a blue selection box the size of the row, the icon or the bar, with its name, like Blizzard's own bars. Clearcasting and Ice Barrier are visible while Edit Mode is open even without the proc or the barrier up, and go back to hidden when it closes. Why says every line \"on screen\" and the group's saved pos is about where you dropped it (x, y from the screen center; a drop beyond a screen edge is pulled back to the edge). After the reload all three are where you dropped them.",
    control = "Drag an action bar the same way: same selection box, same place after the reload. In the SavedVariables, ContextDB.groups[\"mage.cooldowns\"].pos holds the same x, y as Why printed.",
    wrong = "No selection box at all = the library didn't load (press Edit below: it then says \"Edit mode: drag to move\" instead of pointing to Edit Mode). A tiny box = the group frame has no size: Why says \"no size\" (seen 2026-10-10, the 1 px group). The box jumps elsewhere when you drop it, or Why says \"off screen\" or a saved pos far from the drop = the saved offsets don't match the drop point: type /context why mage.blink and copy its center, screen center and scale lines into the note. The group snaps back after the reload = the position callback didn't save. The icons move but the box stays = the group frame and its children came apart." }
S{ "T2", "/context probe out of combat", act = { "probe" },
    "Stand somewhere safe with no target. Press Probe below (the same as /context probe).",
    "Cast Frost Nova, then press Probe again within 20 seconds.",
    "Read the letters in brackets: A = Lua read it plainly, B = an event said so, D = hidden (only the engine can draw it), E = asked first and told it would be hidden here.",
    expect = "First line \"auras restricted now: false\". Frost Nova: \"on cooldown false (A), remaining 0 (A), enabled true (A)\", \"duration object: plain\", \"usable true (A), no power false (A), in range unknown (way A, no-range-check)\" (no target). After the cast: \"on cooldown true (A), remaining 2x.x (A)\". \"Clearcasting on player: present false (A)\". \"main hand enchant: false (A)\" (true with an oil or stone on). Out of combat every letter is A. The \"Cooldown Manager:\" lines are T5's business: \"off\" or \"not tracked\" is fine here.",
    control = "The Frost Nova button on your action bar: its swipe runs while the probe says on cooldown true, and the remaining seconds match.",
    wrong = "Any \"hidden (way E)\" or \"(way D)\" out of combat = the predicates call town values hidden: note the exact line, it changes the design. \"Frost Nova: unknown spell\" = the name wasn't found (another client language, or not trained). A Lua error in chat = a secret reached arithmetic or text: copy the error into the note." }
S{ "T3", "Cooldown group out of combat (spec criterion 1)", crit = 1, act = { "probe", "list" },
    "Out of combat, cast Frost Nova, then Blink. Watch the row of five icons.",
    "Wait until both are ready again (about 25 s and 15 s).",
    expect = "The Frost Nova and Blink icons go grey with a cooldown swipe and a countdown number in the middle; both run down and the icons come back bright at the moment the spells are ready. The three other icons don't change.",
    control = "The same spells on your action bar (or in Blizzard's Cooldown Manager when it's on): the swipes end at the same moment.",
    wrong = "Swipe but no number = the timer text binding (C_DurationUtil) failed. Number but no swipe = SetCooldownFromDurationObject failed. An icon stays grey after the spell is ready = the ready state didn't come back (the refresh missed SPELL_UPDATE_COOLDOWN). The swipe jumps back on every refresh = the 0.2 s tick fed the duration object again." }
S{ "T4", "Ice Barrier bar out of combat (spec criterion 3, the readable half)", crit = 3, act = { "list", "probe_barrier" },
    "You need Ice Barrier (level 40). Out of combat, cast it on yourself and watch under the icon row.",
    "Press List displays right away, and again when the bar is under 5 seconds.",
    "Let the barrier run out (60 s) without fighting.",
    expect = "A bar named Ice Barrier appears below the icons, blue and full, with the spell's icon on the left and a countdown on the right; it empties over 60 s; under 5 s it turns red; it vanishes when the barrier fades. List displays shows mage.icebarrier \"shown\" at first and \"shown low\" under 5 s, with no star (Lua decided it).",
    control = "The Ice Barrier buff in the default buff frame: same remaining time, gone at the same moment.",
    wrong = "Still blue under 5 s = neither the Lua state nor the engine color curve applied (note what List displays said). \"low*\" with a star out of combat = the remaining time read as hidden in town (same finding as T2). The bar stays after the buff is gone = the by-name absence failed out of combat (expected only in combat: F4)." }
S{ "T5", "Cooldown Manager edges", act = { "probe", "probe_barrier", "reload" },
    "Turn Blizzard's Cooldown Manager on and make it track Frost Nova (essential cooldowns) and Ice Barrier (tracked buffs): Esc > Edit Mode > Cooldown Manager and its settings. Then press Reload UI.",
    "Cast Frost Nova, press Probe. When it's ready again, press Probe once more.",
    "Cast Ice Barrier, press Probe Ice Barrier. When it has faded, press it again.",
    expect = "Under Frost Nova a line \"Cooldown Manager: last edge onCooldown, active not read, ready false (B), glow not read\" right after the cast, then \"last edge available, ..., ready true (B)\" once ready. Under Ice Barrier: \"last edge auraApplied\" (or \"active\") with \"active true (B)\" while it's up, \"last edge auraRemoved\" (or \"inactive\") with \"active false (B)\" after.",
    control = "Blizzard's Cooldown Manager itself: its Frost Nova item shows the swipe while we say onCooldown, its Ice Barrier bar is shown while we say active true.",
    wrong = "\"Cooldown Manager: off\" = the game says it isn't available (the option is off, or Forever has none for this character: note it). \"not tracked (no edge seen yet)\" after the cast = the viewer wasn't hooked or its item fired no alert: Reload UI and retry once, then note it. A Lua error naming CooldownViewer = a hook broke Blizzard's code: copy it." }
S{ "T6", "The editor (/context editor)", act = { "editor", "list" },
    "Out of combat, press Editor below (or type /context editor). Click \"Clearcasting\" in the list on the left; read the \"up\" state's line and the line under it.",
    "Under \"Add a state\": click the condition button until it says \"remaining\", leave 5 in the box, click Add. On the new state's \"+ action\" row click the kind button a few times, then Add with \"glow\" selected.",
    "Click the new state's Remove button, then close the window with its X. Then type /dump type(PlaySoundFile) in chat.",
    expect = "The dump prints \"function\" (file and shared-media sounds can play) or \"nil\" (only sound kit IDs do: note it; the addon says so once in chat when a file sound is asked for). A window titled \"Context editor\": left, \"Mage cooldowns\" with its five icons' names indented under it, then Clearcasting and Ice Barrier. Right, for Clearcasting: \"source: aura Clearcasting on player   visibility: whenPresent\", the state \"up: present\" with \"decided by Lua (way A)\" under it (out of combat the absence is read plainly), a color swatch, and its two actions \"glow\" and \"sound 8960\" each with an x. After Add: a state \"remaining<5: remaining < 5\" with \"(may be visual only in combat)\" after its decision line (\"can't say now\" while the proc is absent is right), and its \"+ action\" button cycles through all eight kinds (glow, color, show, hide, sound, speak, screen message, chat line). After Remove the state and its glow are gone. Nothing changes on screen while the proc is absent.",
    control = "Press List displays after the add: it names mage.clearcasting's states only while they hold. Mage Kit's shared editor opens the same color picker on a swatch click.",
    wrong = "The window doesn't open, or chat shows a Lua error = copy it. The list is empty = the saved definitions weren't read. A \"+ action\" button that offers only glow, color, show and hide = the state was marked \"visual only here (way D)\" at the last evaluation: the honesty rule, not a bug (in town that means a hidden read: note it). \"Can't add this action: look-only\" in chat after Add = the same rule, caught on the way in. The picker doesn't open on a swatch click = chat says Blizzard's color picker isn't available." }
S{ "T7", "Cooldown Manager edges fire once (two item frames)", act = { "edge_chat", "probe_barrier", "reload" },
    "Needs T5's setup, plus Ice Barrier in a second place of Blizzard's Cooldown Manager: Esc > Edit Mode > Cooldown Manager settings, make it show both as a tracked buff icon and as a tracked bar (or as an essential cooldown and a tracked buff), then press Reload UI.",
    "Press Edge chat line: it adds a chat line to the Ice Barrier display on the Cooldown Manager's aura-applied edge.",
    "Cast Ice Barrier and count the \"Ice Barrier applied (Cooldown Manager edge)\" lines in chat. Let it fade, cast again, count again. Press Probe Ice Barrier after a cast.",
    "Press Edge chat line again to remove the line.",
    expect = "ONE \"Ice Barrier applied (Cooldown Manager edge)\" line per cast, although two of Blizzard's item frames raise the same alert; the probe says \"last edge auraApplied\" with \"active true (B)\". The second press prints \"removed\" and the next cast prints nothing.",
    control = "T5's setup with Ice Barrier in one place only: one line per cast as well. A Blizzard alert set on the item itself sounds once.",
    wrong = "Two lines per cast = the two items resolved to different spell IDs (the cooldown entry's spell and the buff's linked spell, or two ranks): the de-duplication is by spell ID and edge within one refresh; note both probe lines, the fix is a name key. No line at all = no edge reached the display: the probe says \"not tracked\" (read it like T5) or the name didn't match (the Ice Barrier display is keyed by name): note what the probe printed. One line, then another a moment later = the two alerts came in different frames: note the timing." }

-- F. Near mobs, open world ------------------------------------------------------------------------
S{ "F1", "Counterspell range (spec criterion 5)", crit = 5, act = { "probe_cs" },
    "You need Counterspell (level 24). Out of combat, target a hostile mob from far away (40 yards or more) and look at the Counterspell icon.",
    "Walk toward it until you're within 30 yards, then step back out. Press Probe Counterspell at both distances.",
    "Clear the target (Escape).",
    expect = "Far away the Counterspell icon is tinted red; within range it's back to full color; with no target it's full color too. The probe reads \"in range false (A)\" far away and \"true (A)\" close (\"(B)\" if the range event fired first).",
    control = "Counterspell's button on your action bar: its red out-of-range tint switches at the same distance.",
    wrong = "Never tints, and the probe says \"in range unknown (way A, no-range-check)\" with the target = IsSpellInRange has no answer for this spell here (note it). Tints and never recovers = a stale false was kept (the event came secret and was dropped). The whole row tints = the tint went on the group instead of the icon." }
S{ "F2", "Cooldown group in combat (spec criterion 1)", crit = 1, act = { "probe", "list" },
    "Pull a mob. During the fight cast Frost Nova and Blink (and Counterspell when it casts).",
    "Watch the icons until the spells are ready again, still in the fight if you can.",
    expect = "Same as T3, in the fight: the icons go grey with a swipe and a countdown, and come back bright when ready. Nothing in chat.",
    control = "Your action bar buttons (or Blizzard's Cooldown Manager): same swipe, same end.",
    wrong = "Swipe but the number missing only in combat = the timer text refused the hidden duration (note it: the engine should still count). An icon stays grey after the spell is ready, in combat only = \"ready\" relied on a hidden read (F5 says whether isActive stays A). A \"secret value\" error in chat = copy it with the line." }
S{ "F3", "Clearcasting (spec criterion 2)", crit = 2, act = { "probe", "list" },
    "You need Arcane Concentration (arcane talents). Fight a mob with Frostbolts until Clearcasting procs; watch above the icon row.",
    "Cast the next spell (it consumes the proc). Get a second proc and compare.",
    expect = "The moment it procs, a bigger icon (Clearcasting's) appears above the icon row with a glow around it and a countdown; it vanishes when the next spell consumes it (or 15 s later). The glow starts once per proc, not again on every refresh. The ready-check chime plays once per proc (the display's actions: glow + sound on its \"up\" state) and never again while the proc holds.",
    control = "The Clearcasting buff in the default buff frame appears and vanishes at the same moments.",
    wrong = "Never appears in combat = the read by spell ID (12536) was refused in combat (F5's Clearcasting line says E) and no Cooldown Manager edge stood in: track Clearcasting in the Cooldown Manager and retry. Appears but stays after the next spell = the removal isn't seen in combat (the known gap when the spell isn't tracked there). The glow flickers or restarts = it replays on each refresh. Icon and glow but no chime = the state didn't flip in Lua (its presence read as hidden: F5) or PlaySound refused the kit (note which). A chime on every refresh = the edge fired again." }
S{ "F4", "Ice Barrier in combat (spec criterion 3, the hidden half)", crit = 3, act = { "list", "probe_barrier" },
    "Cast Ice Barrier, pull a mob at once, and keep the fight going past the barrier's last 5 seconds (or recast it mid-fight).",
    "Press List displays during the fight while the bar is under 5 s.",
    expect = "The bar still counts down in combat and still turns red under 5 s. List displays shows \"low*\" (star: visual only, the engine drew it from the color curve) or \"low\" with no star if the remaining time stays readable in open-world combat (F5 tells).",
    control = "The Ice Barrier buff in the default buff frame: its countdown runs at the same pace.",
    wrong = "Stays blue under 5 s in combat = the engine curve wasn't applied (SetColorFromCurve refused) while the Lua state was undecidable. The bar freezes = the duration object stopped (it shouldn't: the engine counts). The bar stays after the barrier ends mid-fight = the known gap when Ice Barrier isn't tracked in the Cooldown Manager: redo with the T5 setup." }
S{ "F5", "/context probe in combat", act = { "probe" },
    "Press Probe out of combat (the control). Then pull a mob, cast Frost Nova, and press Probe mid-fight.",
    "Note the first line and the letters of every line (T2 says what they mean).",
    expect = "The first line says whether open-world combat restricts auras here: \"auras restricted now: true\" or \"false\" (a measurement either way: write it in the note). If true: Frost Nova \"on cooldown true (A)\" (isActive never hides), \"remaining hidden (way E)\", \"duration object: carries hidden values\", usable and no power still (A); \"Clearcasting on player: present hidden (way E)\". If false: the same lines as out of combat. No Lua error.",
    control = "The same probe out of combat a minute earlier: every letter A.",
    wrong = "\"(way D)\" where E was expected = the predicate said plain but the value came back secret (a predicate the game doesn't honor: note the line). \"remaining 12.3 (A)\" next to \"restricted now: true\" = cooldowns and auras restrict separately: note it. A Lua error = a secret reached arithmetic or text: copy it with the line." }

-- D. In a dungeon ---------------------------------------------------------------------------------
S{ "D1", "Cooldown group in a dungeon (spec criterion 1)", crit = 1, act = { "probe", "list" },
    "In any dungeon, out of combat: cast Frost Nova and watch the icons (as in T3).",
    "On a trash pull, cast Frost Nova and Blink and watch (as in F2). A boss fight too if you can.",
    expect = "Same as T3 and F2: swipes, countdowns, icons back when ready. Nothing in chat on entering the dungeon (its lockdown hides unit names, not your cooldowns) nor during the fights.",
    control = "Blizzard's Cooldown Manager in the same dungeon, same pulls.",
    wrong = "Read it like F2. A difference between the open-world fight and the dungeon fight (a number missing here only, an icon stuck here only) is the finding: note what went missing where, and whether it was a boss." }
S{ "D2", "/context probe in a dungeon", act = { "probe" },
    "Press Probe standing in the dungeon out of combat.",
    "Press Probe during a trash fight, and during a boss fight if you can. Write the first line of each in the note.",
    expect = "Out of combat: the same lines as T2, every letter A (your own cooldowns and auras stay readable out of combat in a dungeon, as the group's auras did on 2026-10-05). In the fights: \"auras restricted now: true\" with the E lines of F5. Boss fight: the same, still no error even with the chat lockdown up.",
    control = "T2 (town) and F5 (an open-world fight), done earlier the same day.",
    wrong = "Read it like F5. A dungeon-only difference, such as hidden lines out of combat too, is the finding: note the exact lines and where you stood." }
