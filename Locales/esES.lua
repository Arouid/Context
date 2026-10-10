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

-- Context.lua, Groups.lua, Preset.lua
L["displays: %d, groups: %d"] = "indicadores: %d, grupos: %d"
L["shown"] = "visible"
L["hidden"] = "oculto"
L["All displays removed. /reload to clear the screen."] = "Todos los indicadores eliminados. /reload para limpiar la pantalla."
L["unlocks the displays to drag them (out of combat)"] = "desbloquea los indicadores para arrastrarlos (fuera de combate)"
L["installs a ready-made set of displays"] = "instala un conjunto de indicadores listo para usar"
L["lists the displays and their active states (* = visual only)"] = "lista los indicadores y sus estados activos (* = solo visual)"
L["removes every display and group"] = "elimina todos los indicadores y grupos"
L["Preset installed: %s"] = "Conjunto instalado: %s"
L["Unknown preset: %s"] = "Conjunto desconocido: %s"
L["Edit mode isn't available in combat."] = "El modo de edición no está disponible en combate."
L["Edit mode: drag to move. /context edit again to lock."] = "Modo de edición: arrastra para mover. /context edit de nuevo para bloquear."
L["Edit mode off."] = "Modo de edición desactivado."
L["Edit mode closed: combat started."] = "Modo de edición cerrado: empezó el combate."
L["Mage cooldowns"] = "Reutilizaciones del mago"
L["Clearcasting"] = "Mente despejada"
L["Ice Barrier"] = "Barrera de hielo"
