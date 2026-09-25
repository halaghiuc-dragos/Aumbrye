import test from "node:test";
import assert from "node:assert/strict";
import { createSeededRandom, readSeed } from "./seeded_rng.mjs";

test("identical seeds produce identical random streams", () => {
  const first = createSeededRandom(20260923);
  const second = createSeededRandom(20260923);
  assert.deepEqual(Array.from({ length: 16 }, first), Array.from({ length: 16 }, second));
});

test("different seeds produce different random streams", () => {
  const first = createSeededRandom(11);
  const second = createSeededRandom(12);
  assert.notDeepEqual(Array.from({ length: 8 }, first), Array.from({ length: 8 }, second));
});

test("readSeed accepts an explicit integer and uses its fallback when absent", () => {
  assert.equal(readSeed(["node", "generator"], 9), 9);
  assert.equal(readSeed(["node", "generator", "--seed", "-4"], 9), -4);
  assert.throws(() => readSeed(["node", "generator", "--seed", "later"], 9), /integer/);
});
