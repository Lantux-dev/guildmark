# Desarrollo

## Instalar para desarrollo

Enlaza la carpeta del addon con la del juego (no hace falta copiar nada; los cambios se ven con `/reload`):

```powershell
.\scripts\install-dev.ps1 -WowPath "C:\Program Files (x86)\World of Warcraft" -Flavor _classic_beta_
```

En el juego, activa **Guildmark** en la lista de addons.

## Pruebas fuera del juego

En `tools/` (`cd tools && npm install && npm test`):
- `check.js`: sintaxis Lua 5.1 de todos los archivos del `.toc`.
- `locale.js`: cada texto `L["..."]` del código tiene traducción en `Locales/enUS.lua` (FALTA) y no sobra ninguna (SIN USAR). Los textos tienen que ser literales para que lo detecte.
- `smoke.js` + `smoke.lua`: carga el addon entero con una imitación de la API de WoW (en español y en inglés), pinta todas las vistas con datos de ejemplo y pulsa todos los botones. Detecta errores de Lua, no problemas de aspecto.

`/gmk prueba` convierte tu grupo en una hermandad de prueba ("~Pruebas Horda" / "~Pruebas Alianza") con su propia red, sin tocar la hermandad real.

## Estructura

| Carpeta | Contenido |
|---|---|
| `Core.lua`, `Comm.lua` | Base de datos, comandos, consentimiento, mensajes de hermandad y sincronización |
| `Modules/` | Una funcionalidad por archivo (eventos, mazmorras, caza, auxilio, facción, mercado, logros…) |
| `UI/` | Ventana principal, diálogos, logros, insignias del retrato |
| `Locales/` | Textos; el español es la clave y `enUS.lua` la traducción |
| `Media/` | Arte propio (reservado, ver `NOTICE.md`) |
| `Libs/` | Librerías de terceros |

Los datos se guardan en `GuildmarkDB` (`WTF\Account\<CUENTA>\SavedVariables\Guildmark.lua`), por hermandad en `factionrealm.guilds[<hermandad>]`.

## Librerías

Ace3 (LibStub, CallbackHandler, AceAddon, AceEvent, AceTimer, AceDB, AceConsole, AceComm con ChatThrottleLib), LibSerialize y LibDeflate, en `Guildmark/Libs` con sus licencias.

**LibSerialize está fijada en v1.2.1.** La v1.2.2 comprueba el cero negativo con `1 / num` y el Lua del cliente de Forever lanza "Division by zero", así que falla al serializar cualquier 0. No actualizar hasta que se corrija.
