/** Small, stable 32-bit PRNG for reproducible generated assets. */
export function createSeededRandom(seed) {
  if (!Number.isSafeInteger(seed)) throw new TypeError("seed must be a safe integer");
  let state = seed >>> 0;
  return function nextRandom() {
    state = (state + 0x6d2b79f5) >>> 0;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

export function readSeed(argv, fallback) {
  const index = argv.indexOf("--seed");
  if (index < 0) return fallback;
  const raw = argv[index + 1];
  if (raw === undefined || !/^-?\d+$/.test(raw)) {
    throw new Error("--seed requires an integer value");
  }
  const seed = Number(raw);
  if (!Number.isSafeInteger(seed)) throw new Error("--seed must be a safe integer");
  return seed;
}
