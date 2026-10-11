# Context

A World of Warcraft addon (forever). Type `/context` in game.

Contextual cooldowns and auras for WoW: Forever, where most combat values are hidden from addons:
the spec is [docs/specs/contextual-cooldowns.md](docs/specs/contextual-cooldowns.md). So far:
the sources (`Sources.lua`), the condition evaluator (`Conditions.lua`), icon and bar displays in
groups fed by duration objects (`Displays.lua`, `Widgets.lua`, `Groups.lua`), the "Mage essentials"
preset (`/context preset mage`, installed on a mage's first login), Blizzard's Cooldown Manager
hooked as an optional source of edges for the spells tracked there (`CooldownManager.lua`), `/context edit` to drag things
around out of combat, and `/context probe [spell]`, which prints what the sources can read about a
spell and its aura, in and out of combat. A display's states carry actions (`Actions.lua`): glow,
color, show or hide while the state holds; a sound, spoken text, a screen message or a chat line
once when it flips, and only when Lua decided it (a hidden value never makes a sound).
`/context editor` lists the displays, shows each state as a sentence with how it was decided, and
adds states from ready-made conditions and actions to them. `/context why [displayId]` prints
what decides whether a display can be seen (size, anchor, parent, alpha, shown state, its center
against the screen). `/context tests` opens the
step-by-step in-game test guide (the rows of `docs/verified-in-game.md`; answers saved in
`ContextDB.testGuide`).

What has been seen working in game, and when: [docs/verified-in-game.md](docs/verified-in-game.md).

## License

Context is free software: you can redistribute it and/or modify it under the terms of the GNU
General Public License as published by the Free Software Foundation, either version 2 of the
License, or (at your option) any later version. It is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; see [LICENSE](LICENSE) (GPL version 2) for details.

Code taken from other addons keeps its own license and author credit, marked in the file it is in.
`Libs/LibEditMode` is [LibEditMode](https://github.com/p3lim-wow/LibEditMode) by p3lim, embedded
unmodified under its own license (`Libs/LibEditMode/LICENSE.txt`).
Code from GPL-2.0-only projects (WeakAuras, EverAuras) makes the addon as a whole distributable under
GPL version 2.
