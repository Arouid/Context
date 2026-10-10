# Verified in game: Context

The checks show that the code compiles and that the logic tests pass. Whether a feature works in
the game is only known by trying it there. This file keeps track of what was seen working, when,
and on which build, so "it probably works" doesn't stay that way for months.

One line per session, newest first:

```
- YYYY-MM-DD HH:MM - <commit> - <game build> - <works | broken | partly> - <what you saw, and what you didn't get to>
```

`<commit>` is the last commit that was actually loaded in the game during the session. Write a line
only after seeing it in game, and say what wasn't tested as well as what was.

## Test guide: built, not yet seen in game

Same shape as Mage Kit's checklist: what to do, what you should see, and the known-good control
that tells a broken feature from a wrong expectation. A confirmed row becomes a line in the log.
Before starting: `/reload` on a mage (the "Mage essentials" preset installs itself on the first
login with no displays; `/context preset mage` otherwise).

| # | Feature | Do | Expect |
|---|---|---|---|
| T1 | Edit Mode placement (spec criterion 4) | Out of combat: Esc > Edit Mode. Drag the box labeled "Mage cooldowns" somewhere else, then the "Clearcasting" and "Ice Barrier" boxes. Leave Edit Mode (Done or Esc). `/reload`, then open Edit Mode once more | In Edit Mode each of the three shows a blue selection box with its name, like Blizzard's own bars (control: drag an action bar the same way); Clearcasting and Ice Barrier are visible while Edit Mode is open even without the proc or the barrier up, and go back to hidden when it closes. After `/reload` all three are where you dropped them, and `ContextDB.groups["mage.cooldowns"].pos` in the SavedVariables holds the new x, y. Outcomes: no selection box at all = the library didn't load (`/context edit` then says "Edit mode: drag to move" instead of pointing to Edit Mode); the box is there but the group snaps back after `/reload` = the position callback didn't save; the icons move but the box stays = the group frame and its children came apart |

## Log
