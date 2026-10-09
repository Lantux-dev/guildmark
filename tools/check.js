// Comprueba la sintaxis (Lua 5.1) de todos los .lua que carga el .toc del addon.
const fs = require('fs'), path = require('path'), lp = require('luaparse');
const root = process.argv[2] || path.join(__dirname, '..', 'Guildmark');
let bad = 0;
const toc = fs.readFileSync(path.join(root, 'Guildmark.toc'), 'utf8')
  .split(/\r?\n/).map(l => l.trim()).filter(l => l.endsWith('.lua'));
for (const f of toc) {
  const p = path.join(root, ...f.split(String.fromCharCode(92)));
  const src = fs.readFileSync(p, 'utf8');
  try { lp.parse(src, { luaVersion: '5.1' }); }
  catch (e) { bad++; console.log('FAIL', f, e.message); continue; }
  // Rutas de texturas con una sola barra invertida ("Interface\Icons"): luaparse
  // las acepta, pero el Lua del juego da "invalid escape sequence".
  const BS = String.fromCharCode(92);
  const single = new RegExp('"Interface' + BS + BS + '(?!' + BS + BS + ')', 'g');
  const lines = src.split(/\r?\n/).map((l, i) => [i + 1, l]).filter(([, l]) => single.test(l) && !(single.lastIndex = 0));
  if (lines.length) { bad++; console.log('FAIL', f, 'barra invertida simple en la línea', lines.map(([n]) => n).join(', ')); continue; }
  console.log('OK  ', f);
}
process.exit(bad);
