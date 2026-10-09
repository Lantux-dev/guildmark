// Textos traducibles del addon.
//
// Los textos se escriben en español directamente en el código como L["..."]:
// la clave es el propio texto en español. Este script los recoge todos y
// comprueba que Locales/enUS.lua tenga su traducción, con los mismos huecos de
// formato (%s, %d...) en el mismo orden.
//
//   node locale.js           comprueba (falla si falta alguna traducción)
//   node locale.js --missing lista las que faltan, listas para copiar
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'Guildmark');
const BS = String.fromCharCode(92);

function luaFiles() {
  return fs.readFileSync(path.join(root, 'Guildmark.toc'), 'utf8')
    .split(/\r?\n/).map(l => l.trim()).filter(l => l.endsWith('.lua'))
    .map(f => f.split(BS).join('/'))
    .filter(f => !f.startsWith('Locales/'));
}

// Recorre el código y saca las cadenas L["..."] (respetando escapes).
function extractKeys(src) {
  const keys = [];
  let i = 0;
  while ((i = src.indexOf('L["', i)) !== -1) {
    let j = i + 3;
    let raw = '';
    while (j < src.length && src[j] !== '"') {
      if (src[j] === BS) { raw += src[j] + src[j + 1]; j += 2; } else { raw += src[j++]; }
    }
    keys.push(raw);
    i = j + 1;
  }
  return keys;
}

// Traducciones del archivo de inglés: L["clave"] = "traducción"
function extractTranslations(src) {
  const map = new Map();
  const re = /^\s*L\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"/gm;
  let m;
  while ((m = re.exec(src))) map.set(m[1], m[2]);
  return map;
}

const placeholders = s => (s.match(/%[-+0-9.]*[sdif]/g) || []).join(' ');

const used = new Map();
for (const f of luaFiles()) {
  // Sin las líneas de comentario (pueden mencionar L["..."] como ejemplo).
  const code = fs.readFileSync(path.join(root, f), 'utf8')
    .split(/\r?\n/)
    .filter(l => !l.trim().startsWith('--'))
    .join('\n');
  for (const k of extractKeys(code)) {
    if (!used.has(k)) used.set(k, f);
  }
}

const enPath = path.join(root, 'Locales', 'enUS.lua');
const en = fs.existsSync(enPath) ? extractTranslations(fs.readFileSync(enPath, 'utf8')) : new Map();

const missing = [...used.keys()].filter(k => !en.has(k));
const badFormat = [...used.keys()].filter(k => en.has(k) && placeholders(k) !== placeholders(en.get(k)));
const unused = [...en.keys()].filter(k => !used.has(k));

if (process.argv.includes('--missing')) {
  for (const k of missing) console.log(`L["${k}"] = ""  -- ${used.get(k)}`);
  process.exit(0);
}

console.log(`Textos: ${used.size} · traducidos al inglés: ${used.size - missing.length} · sin usar en el código: ${unused.length}`);
for (const k of unused) console.log(`SIN USAR: "${k}"`);
for (const k of badFormat) console.log(`FORMATO distinto: "${k}" -> "${en.get(k)}"`);
for (const k of missing.slice(0, 20)) console.log(`FALTA: "${k}" (${used.get(k)})`);
if (missing.length > 20) console.log(`... y ${missing.length - 20} más (node locale.js --missing)`);
process.exit(missing.length || badFormat.length ? 1 : 0);
