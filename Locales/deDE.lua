-- Locales/deDE.lua: German. Loaded after enUS.lua; does nothing on another client.
local _, ns = ...
if GetLocale() ~= "deDE" then return end

local L = ns.L
L["loaded. Type /%s for help."] = "geladen. Gib /%s für die Hilfe ein."
L["version %s"] = "Version %s"
L["Commands:"] = "Befehle:"
L["shows the version"] = "zeigt die Version"
L["prints what the sources answer for a spell (default: Frost Nova and Clearcasting)"] = "zeigt, was die Quellen zu einem Zauber sagen (Standard: Frostnova und Freizaubern)"

-- Probe.lua
L["not read"] = "nicht gelesen"
L["hidden (way %s)"] = "verborgen (Weg %s)"
L["unknown (way %s, %s)"] = "unbekannt (Weg %s, %s)"
L["%s: unknown spell"] = "%s: unbekannter Zauber"
L["on cooldown"] = "in Abklingzeit"
L["remaining"] = "verbleibend"
L["enabled"] = "aktiv"
L["duration object: %s"] = "Dauerobjekt: %s"
L["carries hidden values"] = "enthält verborgene Werte"
L["plain"] = "lesbar"
L["charges"] = "Aufladungen"
L["usable"] = "nutzbar"
L["no power"] = "keine Ressource"
L["in range"] = "in Reichweite"
L["on %s"] = "auf %s"
L["present"] = "vorhanden"
L["stacks"] = "Stapel"
L["auras restricted now: %s"] = "Auren jetzt eingeschränkt: %s"
L["main hand enchant"] = "Waffenhand-Verzauberung"
