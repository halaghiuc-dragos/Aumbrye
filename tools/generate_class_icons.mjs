#!/usr/bin/env node
import { writeFileSync } from "node:fs";
import { deflateSync } from "node:zlib";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const TEXTURE = resolve(ROOT, "apps/game/client/assets/ui/atlas/class_icons.png");
const MANIFEST = resolve(ROOT, "content/ui/class_icon_atlas.json");
const CELL = 64;

const CELLS = [
  { id: "berserker", rgb: [180, 60, 50] },
  { id: "knight", rgb: [120, 130, 150] },
  { id: "rogue", rgb: [70, 120, 80] },
  { id: "scholar", rgb: [150, 110, 200] },
  { id: "sentinel", rgb: [90, 90, 110] },
  { id: "hunter", rgb: [122, 96, 58] },
  { id: "herald", rgb: [176, 158, 104] },
];

function crc32(buf) {
  let c;
  const table = crc32.table || (crc32.table = (() => {
    const t = new Int32Array(256);
    for (let n = 0; n < 256; n += 1) {
      c = n;
      for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c;
    }
    return t;
  })());
  let crc = -1;
  for (let i = 0; i < buf.length; i += 1) crc = table[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ -1) >>> 0;
}

function chunk(tag, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(tag, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

function writePng(path, width, height, rgb) {
  const stride = width * 3;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0;
    rgb.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
  writeFileSync(path, png);
}

const width = CELLS.length * CELL;
const pixels = Buffer.alloc(width * CELL * 3);
CELLS.forEach((cell, index) => {
  for (let y = 0; y < CELL; y += 1) {
    for (let x = 0; x < CELL; x += 1) {
      const offset = (y * width + index * CELL + x) * 3;
      pixels[offset] = cell.rgb[0];
      pixels[offset + 1] = cell.rgb[1];
      pixels[offset + 2] = cell.rgb[2];
    }
  }
});
writePng(TEXTURE, width, CELL, pixels);

const manifest = {
  schemaVersion: 1,
  texture: "res://assets/ui/atlas/class_icons.png",
  cellSize: CELL,
  columns: CELLS.length,
  rows: 1,
  unknown: { col: 0, row: 0 },
  cells: {},
};
CELLS.forEach((cell, index) => {
  manifest.cells[cell.id] = { col: index, row: 0 };
});
writeFileSync(MANIFEST, `${JSON.stringify(manifest, null, 2)}\n`);

console.log(`class_icons.png ${width}x${CELL} with ${CELLS.length} cells`);
