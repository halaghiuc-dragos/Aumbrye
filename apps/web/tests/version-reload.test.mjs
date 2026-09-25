import assert from "node:assert/strict";
import test from "node:test";
import { beginVersionReload, clearVersionReloadAttempt, RELOAD_ATTEMPTED_KEY } from "../src/components/version-reload.ts";

function memoryStorage() {
  const values = new Map();
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
  };
}

test("first version mismatch reloads with a cache-busting query while preserving route state", () => {
  const storage = memoryStorage();
  const result = beginVersionReload(storage, "https://game.example/wiki/guide?lang=ro#combat", 1234);
  assert.equal(result, "https://game.example/wiki/guide?lang=ro&v=1234#combat");
  assert.equal(storage.getItem(RELOAD_ATTEMPTED_KEY), "1234");
});

test("repeated stale-CDN mismatch is suppressed until a successful API response clears the guard", () => {
  const storage = memoryStorage();
  beginVersionReload(storage, "https://game.example/?v=old", 1);
  assert.equal(beginVersionReload(storage, "https://game.example/?v=old", 2), undefined);
  clearVersionReloadAttempt(storage);
  assert.equal(beginVersionReload(storage, "https://game.example/?v=old", 3), "https://game.example/?v=3");
});

test("unavailable or throwing session storage fails closed and leaves manual reload available", () => {
  assert.equal(beginVersionReload(undefined, "https://game.example/", 1), undefined);
  assert.equal(beginVersionReload(() => { throw new DOMException("denied", "SecurityError"); }, "https://game.example/", 1), undefined);
  const denied = {
    getItem() { throw new DOMException("denied", "SecurityError"); },
    setItem() { throw new DOMException("denied", "SecurityError"); },
    removeItem() { throw new DOMException("denied", "SecurityError"); },
  };
  assert.equal(beginVersionReload(denied, "https://game.example/", 1), undefined);
  assert.doesNotThrow(() => clearVersionReloadAttempt(denied));
  assert.doesNotThrow(() => clearVersionReloadAttempt(() => { throw new DOMException("denied", "SecurityError"); }));
});
