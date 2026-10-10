-- Locales/frFR.lua: French. Loaded after enUS.lua; does nothing on another client.
local _, ns = ...
if GetLocale() ~= "frFR" then return end

local L = ns.L
L["loaded. Type /%s for help."] = "chargé. Tape /%s pour l'aide."
L["version %s"] = "version %s"
L["Commands:"] = "Commandes :"
L["shows the version"] = "affiche la version"
L["prints what the sources answer for a spell (default: Frost Nova and Clearcasting)"] = "affiche ce que les sources répondent pour un sort (par défaut : Nova de givre et Clairvoyance)"

-- Probe.lua
L["not read"] = "non lu"
L["hidden (way %s)"] = "caché (voie %s)"
L["unknown (way %s, %s)"] = "inconnu (voie %s, %s)"
L["%s: unknown spell"] = "%s : sort inconnu"
L["on cooldown"] = "en recharge"
L["remaining"] = "restant"
L["enabled"] = "actif"
L["duration object: %s"] = "objet durée : %s"
L["carries hidden values"] = "porte des valeurs cachées"
L["plain"] = "lisible"
L["charges"] = "charges"
L["usable"] = "utilisable"
L["no power"] = "sans ressource"
L["in range"] = "à portée"
L["on %s"] = "sur %s"
L["present"] = "présent"
L["stacks"] = "cumuls"
L["auras restricted now: %s"] = "auras restreintes maintenant : %s"
L["main hand enchant"] = "enchantement main droite"

-- Context.lua, Groups.lua, Preset.lua
L["displays: %d, groups: %d"] = "affichages : %d, groupes : %d"
L["shown"] = "visible"
L["hidden"] = "masqué"
L["All displays removed. /reload to clear the screen."] = "Tous les affichages supprimés. /reload pour nettoyer l'écran."
L["unlocks the displays to drag them (out of combat; Blizzard's Edit Mode when the library is loaded)"] = "déverrouille les affichages pour les déplacer (hors combat ; le mode Édition de Blizzard quand la bibliothèque est chargée)"
L["installs a ready-made set of displays"] = "installe un jeu d'affichages prêt à l'emploi"
L["lists the displays and their active states (* = visual only)"] = "liste les affichages et leurs états actifs (* = visuel seulement)"
L["removes every display and group"] = "supprime tous les affichages et groupes"
L["Preset installed: %s"] = "Jeu installé : %s"
L["Unknown preset: %s"] = "Jeu inconnu : %s"
L["Edit mode isn't available in combat."] = "Le mode édition n'est pas disponible en combat."
L["Edit mode: drag to move. /context edit again to lock."] = "Mode édition : glisse pour déplacer. /context edit à nouveau pour verrouiller."
L["Edit mode off."] = "Mode édition désactivé."
L["Edit mode closed: combat started."] = "Mode édition fermé : le combat a commencé."
L["The displays are in Blizzard's Edit Mode: Esc, then Edit Mode."] = "Les affichages sont dans le mode Édition de Blizzard : Échap, puis Mode Édition."
L["Mage cooldowns"] = "Recharges du mage"
L["Clearcasting"] = "Clairvoyance"
L["Ice Barrier"] = "Barrière de glace"

-- CooldownManager.lua (via Probe.lua)
L["Cooldown Manager: off"] = "Gestionnaire de recharges : désactivé"
L["Cooldown Manager: not tracked (no edge seen yet)"] = "Gestionnaire de recharges : non suivi (aucun front vu)"
L["Cooldown Manager: last edge %s, active %s, ready %s, glow %s"] = "Gestionnaire de recharges : dernier front %s, actif %s, prêt %s, lueur %s"
