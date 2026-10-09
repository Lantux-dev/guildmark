// Ejecuta smoke.lua en fengari pasándole el código de cada archivo del .toc.
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..', 'Guildmark').split(String.fromCharCode(92)).join('/');
const files = fs.readFileSync(path.join(root, 'Guildmark.toc'), 'utf8')
  .split(/\r?\n/).map(l => l.trim()).filter(l => l.endsWith('.lua'));
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
// SOURCES = { { name = ..., src = ... }, ... } usando cadenas largas de Lua.
const eq = '='.repeat(8);
let sources = 'SOURCES = {\n';
for (const f of files) {
  const src = fs.readFileSync(path.join(root, ...f.split(String.fromCharCode(92))), 'utf8');
  sources += `{ name = "${f.split(String.fromCharCode(92)).join('/')}", src = [${eq}[\n${src}]${eq}] },\n`;
}
sources += '}\n';
// SMOKE_LOCALE=enUS node smoke.js prueba el addon con un cliente en inglés.
const locale = process.env.SMOKE_LOCALE || 'esES';
const code = `ADDON_ROOT = "${root}"\nSMOKE_LOCALE = "${locale}"\n` + sources + fs.readFileSync(path.join(__dirname, 'smoke.lua'), 'utf8');
if (lauxlib.luaL_dostring(L, to_luastring(code)) !== 0) {
  console.log('ERROR:', lua.lua_tojsstring(L, -1));
  process.exit(1);
}
