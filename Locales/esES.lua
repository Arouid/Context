-- Locales/esES.lua: Spanish, for esES and esMX clients. Loaded after enUS.lua; does nothing on
-- another client.
local _, ns = ...
local locale = GetLocale()
if locale ~= "esES" and locale ~= "esMX" then return end

local L = ns.L
L["loaded. Type /%s for help."] = "cargado. Escribe /%s para ver la ayuda."
L["version %s"] = "versión %s"
L["Commands:"] = "Comandos:"
L["shows the version"] = "muestra la versión"
L["prints what the sources answer for a spell (default: Frost Nova and Clearcasting)"] = "muestra lo que responden las fuentes para un hechizo (por defecto: Nova de Escarcha y Mente despejada)"

-- Probe.lua
L["not read"] = "no leído"
L["hidden (way %s)"] = "oculto (vía %s)"
L["unknown (way %s, %s)"] = "desconocido (vía %s, %s)"
L["%s: unknown spell"] = "%s: hechizo desconocido"
L["on cooldown"] = "en reutilización"
L["remaining"] = "restante"
L["enabled"] = "activo"
L["duration object: %s"] = "objeto de duración: %s"
L["carries hidden values"] = "contiene valores ocultos"
L["plain"] = "legible"
L["charges"] = "cargas"
L["usable"] = "utilizable"
L["no power"] = "sin recurso"
L["in range"] = "a distancia"
L["on %s"] = "en %s"
L["present"] = "presente"
L["stacks"] = "acumulaciones"
L["auras restricted now: %s"] = "auras restringidas ahora: %s"
L["main hand enchant"] = "encantamiento de mano derecha"
