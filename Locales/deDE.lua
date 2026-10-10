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

-- Context.lua, Groups.lua, Preset.lua
L["displays: %d, groups: %d"] = "Anzeigen: %d, Gruppen: %d"
L["shown"] = "sichtbar"
L["hidden"] = "verborgen"
L["All displays removed. /reload to clear the screen."] = "Alle Anzeigen entfernt. /reload räumt den Bildschirm auf."
L["unlocks the displays to drag them (out of combat; Blizzard's Edit Mode when the library is loaded)"] = "entsperrt die Anzeigen zum Verschieben (außerhalb des Kampfes; Blizzards Bearbeitungsmodus, wenn die Bibliothek geladen ist)"
L["installs a ready-made set of displays"] = "installiert einen fertigen Satz Anzeigen"
L["lists the displays and their active states (* = visual only)"] = "listet die Anzeigen und ihre aktiven Zustände (* = nur visuell)"
L["removes every display and group"] = "entfernt alle Anzeigen und Gruppen"
L["Preset installed: %s"] = "Satz installiert: %s"
L["Unknown preset: %s"] = "Unbekannter Satz: %s"
L["Edit mode isn't available in combat."] = "Der Bearbeitungsmodus ist im Kampf nicht verfügbar."
L["Edit mode: drag to move. /context edit again to lock."] = "Bearbeitungsmodus: ziehen zum Verschieben. Erneut /context edit zum Sperren."
L["Edit mode off."] = "Bearbeitungsmodus aus."
L["Edit mode closed: combat started."] = "Bearbeitungsmodus beendet: Kampf begonnen."
L["The displays are in Blizzard's Edit Mode: Esc, then Edit Mode."] = "Die Anzeigen sind in Blizzards Bearbeitungsmodus: Esc, dann Bearbeitungsmodus."
L["Mage cooldowns"] = "Magier-Abklingzeiten"
L["Clearcasting"] = "Freizaubern"
L["Ice Barrier"] = "Eisbarriere"

-- CooldownManager.lua (via Probe.lua)
L["Cooldown Manager: off"] = "Abklingzeiten-Manager: aus"
L["Cooldown Manager: not tracked (no edge seen yet)"] = "Abklingzeiten-Manager: nicht verfolgt (noch keine Flanke gesehen)"
L["Cooldown Manager: last edge %s, active %s, ready %s, glow %s"] = "Abklingzeiten-Manager: letzte Flanke %s, aktiv %s, bereit %s, Leuchten %s"

-- TestGuide.lua (the guide itself stays in English: a testing tool)
L["opens the step-by-step in-game test guide (testing)"] = "öffnet die Schritt-für-Schritt-Testanleitung im Spiel (Test)"
