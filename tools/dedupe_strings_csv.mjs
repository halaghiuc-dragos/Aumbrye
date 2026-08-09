import fs from "fs";
import path from "path";

const ROOT = path.resolve(
  path.dirname(new URL(import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, "$1"),
  ".."
);
const P = path.join(ROOT, "apps/game/client/translations/strings.csv");

const raw = fs.readFileSync(P, "utf8");
const eol = raw.includes("\r\n") ? "\r\n" : "\n";
const lines = raw.split(/\r?\n/);

function keyOf(line) {
  if (!line.trim()) return null;
  if (line.startsWith('"')) {
    const m = line.match(/^"((?:[^"]|"")*)"/);
    return m ? m[1].replace(/""/g, '"') : null;
  }
  const i = line.indexOf(",");
  return i < 0 ? null : line.slice(0, i);
}

const header = lines[0];
const body = lines.slice(1).filter((l) => l.trim().length > 0);

// keep the LAST occurrence of each key, in its original position
const lastIndex = new Map();
body.forEach((l, i) => {
  const k = keyOf(l);
  if (k) lastIndex.set(k, i);
});

const kept = body.filter((l, i) => {
  const k = keyOf(l);
  if (!k) return true;
  return lastIndex.get(k) === i;
});

const removed = body.length - kept.length;
fs.writeFileSync(P, [header, ...kept].join(eol) + eol);
console.log("rows before:", body.length, " after:", kept.length, " duplicates removed:", removed);
