import fs from "fs";
import path from "path";
import zlib from "zlib";

const ROOT = path.resolve(
  path.dirname(new URL(import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, "$1"),
  ".."
);
const PNG_OUT = path.join(ROOT, "apps/game/client/assets/ui/input_glyphs.png");
const JSON_OUT = path.join(ROOT, "content/ui/input_glyph_atlas.json");

const CELL = 16;
const COLS = 8;

const FONT = {
  A: ["010", "101", "111", "101", "101"], B: ["110", "101", "110", "101", "110"],
  C: ["011", "100", "100", "100", "011"], D: ["110", "101", "101", "101", "110"],
  E: ["111", "100", "110", "100", "111"], F: ["111", "100", "110", "100", "100"],
  G: ["011", "100", "101", "101", "011"], H: ["101", "101", "111", "101", "101"],
  I: ["111", "010", "010", "010", "111"], J: ["001", "001", "001", "101", "010"],
  K: ["101", "101", "110", "101", "101"], L: ["100", "100", "100", "100", "111"],
  M: ["101", "111", "111", "101", "101"], N: ["101", "111", "111", "111", "101"],
  O: ["010", "101", "101", "101", "010"], P: ["110", "101", "110", "100", "100"],
  Q: ["010", "101", "101", "111", "011"], R: ["110", "101", "110", "101", "101"],
  S: ["011", "100", "010", "001", "110"], T: ["111", "010", "010", "010", "010"],
  U: ["101", "101", "101", "101", "111"], V: ["101", "101", "101", "101", "010"],
  W: ["101", "101", "111", "111", "101"], X: ["101", "101", "010", "101", "101"],
  Y: ["101", "101", "010", "010", "010"], Z: ["111", "001", "010", "100", "111"],
  0: ["111", "101", "101", "101", "111"], 1: ["010", "110", "010", "010", "111"],
  2: ["110", "001", "010", "100", "111"], 3: ["110", "001", "010", "001", "110"],
  4: ["101", "101", "111", "001", "001"], 5: ["111", "100", "110", "001", "110"],
  6: ["011", "100", "111", "101", "111"], 7: ["111", "001", "010", "010", "010"],
  8: ["111", "101", "111", "101", "111"], 9: ["111", "101", "111", "001", "110"],
  "-": ["000", "000", "111", "000", "000"],
};

const LABEL = {
  ESCAPE: "ESC", ENTER: "ENT", TAB: "TAB", SPACE: "SPC", CTRL: "CTL",
  HOME: "HOM", BACKSPACE: "BSP", DELETE: "DEL", SHIFT: "SHF", ALT: "ALT",
};
const ARROW = { LEFT: "left", RIGHT: "right", UP: "up", DOWN: "down" };

const KEYS = [
  "1","2","3","4","A","C","CTRL","D","DOWN","E","ENTER","ESCAPE","F","F1","F11","F2",
  "H","HOME","K","LEFT","M","P","Q","R","RIGHT","S","SPACE","T","TAB","UP","V","W",
  "SHIFT","ALT","B","G","I","J","L","N","O","U","X","Y","Z","5","6","7","8","9","0",
  "DELETE","BACKSPACE","END","PAGEUP","PAGEDOWN","INSERT",
  "F3","F4","F5","F6","F7","F8","F9","F10","F12",
];
const BUTTONS = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14];
const AXES = [0,1,2,3,4,5];

const BG = [24, 22, 28, 255];
const CAP = [58, 54, 64, 255];
const EDGE = [96, 90, 104, 255];
const INK = [226, 220, 208, 255];

function makeCanvas(w, h) {
  const px = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    px[i * 4 + 0] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; px[i * 4 + 3] = 0;
  }
  return { w, h, px };
}

function set(c, x, y, rgba) {
  if (x < 0 || y < 0 || x >= c.w || y >= c.h) return;
  const i = (y * c.w + x) * 4;
  c.px[i] = rgba[0]; c.px[i + 1] = rgba[1]; c.px[i + 2] = rgba[2]; c.px[i + 3] = rgba[3];
}

function keycap(c, ox, oy) {
  for (let y = 2; y <= 13; y++) for (let x = 1; x <= 14; x++) set(c, ox + x, oy + y, CAP);
  for (let x = 2; x <= 13; x++) { set(c, ox + x, oy + 1, EDGE); set(c, ox + x, oy + 14, EDGE); }
  for (let y = 2; y <= 13; y++) { set(c, ox + 0, oy + y, EDGE); set(c, ox + 15, oy + y, EDGE); }
}

function drawText(c, ox, oy, text) {
  const glyphs = text.split("").filter((ch) => FONT[ch]);
  const w = glyphs.length * 3 + (glyphs.length - 1);
  let x = ox + Math.floor((CELL - w) / 2);
  const y = oy + 5;
  for (const ch of glyphs) {
    const rows = FONT[ch];
    for (let ry = 0; ry < 5; ry++)
      for (let rx = 0; rx < 3; rx++)
        if (rows[ry][rx] === "1") set(c, x + rx, y + ry, INK);
    x += 4;
  }
}

function drawArrow(c, ox, oy, dir) {
  const cx = ox + 8, cy = oy + 8;
  for (let i = 0; i < 4; i++) {
    for (let j = -i; j <= i; j++) {
      if (dir === "up") set(c, cx + j, cy - 2 + i, INK);
      if (dir === "down") set(c, cx + j, cy + 2 - i, INK);
      if (dir === "left") set(c, cx - 2 + i, cy + j, INK);
      if (dir === "right") set(c, cx + 2 - i, cy + j, INK);
    }
  }
}

function circle(c, ox, oy, r, rgba) {
  const cx = ox + 8, cy = oy + 8;
  for (let y = -r; y <= r; y++)
    for (let x = -r; x <= r; x++)
      if (x * x + y * y <= r * r) set(c, cx + x, cy + y, rgba);
}

function encodePng(c) {
  const raw = Buffer.alloc((c.w * 4 + 1) * c.h);
  let o = 0;
  for (let y = 0; y < c.h; y++) {
    raw[o++] = 0;
    for (let x = 0; x < c.w; x++) {
      const i = (y * c.w + x) * 4;
      raw[o++] = c.px[i]; raw[o++] = c.px[i + 1]; raw[o++] = c.px[i + 2]; raw[o++] = c.px[i + 3];
    }
  }
  const idat = zlib.deflateSync(raw, { level: 9 });
  const chunks = [];
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(c.w, 0); ihdr.writeUInt32BE(c.h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
    const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td) >>> 0, 0);
    return Buffer.concat([len, td, crc]);
  };
  chunks.push(sig, chunk("IHDR", ihdr), chunk("IDAT", idat), chunk("IEND", Buffer.alloc(0)));
  return Buffer.concat(chunks);
}

let CRC_TABLE = null;
function crc32(buf) {
  if (!CRC_TABLE) {
    CRC_TABLE = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      CRC_TABLE[n] = c;
    }
  }
  let crc = -1;
  for (let i = 0; i < buf.length; i++) crc = CRC_TABLE[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return crc ^ -1;
}

const cells = {};
const entries = [];
for (const k of KEYS) entries.push({ key: "keyboard/" + k, kind: "key", label: k });
for (const b of BUTTONS) entries.push({ key: "xbox/" + b, kind: "pad", label: String(b) });
for (const b of BUTTONS) entries.push({ key: "playstation/" + b, kind: "pad", label: String(b) });
for (const b of BUTTONS) entries.push({ key: "generic/" + b, kind: "pad", label: String(b) });
for (const a of AXES) entries.push({ key: "xbox/axis_" + a, kind: "axis", label: String(a) });
for (const a of AXES) entries.push({ key: "playstation/axis_" + a, kind: "axis", label: String(a) });
for (const a of AXES) entries.push({ key: "generic/axis_" + a, kind: "axis", label: String(a) });
entries.push({ key: "__unknown__", kind: "key", label: "-" });

const rows = Math.ceil(entries.length / COLS);
const canvas = makeCanvas(COLS * CELL, rows * CELL);

entries.forEach((e, idx) => {
  const col = idx % COLS;
  const row = Math.floor(idx / COLS);
  const ox = col * CELL;
  const oy = row * CELL;
  if (e.kind === "pad" || e.kind === "axis") {
    circle(canvas, ox, oy, 7, EDGE);
    circle(canvas, ox, oy, 6, CAP);
    drawText(canvas, ox, oy, e.label);
  } else {
    keycap(canvas, ox, oy);
    if (ARROW[e.label]) drawArrow(canvas, ox, oy, ARROW[e.label]);
    else drawText(canvas, ox, oy, LABEL[e.label] || e.label);
  }
  if (e.key !== "__unknown__") cells[e.key] = { col, row };
  else cells.__unknownCell = { col, row };
});

const unknown = cells.__unknownCell;
delete cells.__unknownCell;

fs.mkdirSync(path.dirname(PNG_OUT), { recursive: true });
fs.writeFileSync(PNG_OUT, encodePng(canvas));

const manifest = {
  schemaVersion: 1,
  texture: "res://assets/ui/input_glyphs.png",
  cellSize: CELL,
  columns: COLS,
  rows,
  unknown,
  cells,
};
const eol = fs.existsSync(JSON_OUT) && fs.readFileSync(JSON_OUT, "utf8").includes("\r\n") ? "\r\n" : "\n";
fs.writeFileSync(JSON_OUT, JSON.stringify(manifest, null, 2).replace(/\n/g, eol) + eol);

console.log("png:", PNG_OUT.split(/[\\/]/).pop(), canvas.w + "x" + canvas.h);
console.log("cells:", Object.keys(cells).length, "rows:", rows);
