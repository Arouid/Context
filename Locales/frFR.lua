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
