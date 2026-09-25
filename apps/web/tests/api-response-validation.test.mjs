import assert from "node:assert/strict";
import test from "node:test";
import {
  decodeAuthResponse,
  decodeHealthResponse,
  decodeLeaderboardResponse,
  decodeSaveResponse,
  InvalidApiPayloadError,
} from "../src/api/response-validation.ts";
import { VersionMismatchError, getLeaderboards, request } from "../src/api/client.ts";

const path = "/api/test";

test("auth decoder accepts cookie transport responses without a body refresh token", () => {
  const response = {
    tokens: { accessToken: "access", accessTokenExpiresAt: "2026-09-23T00:00:00Z" },
    user: { id: "account-id", email: null },
  };
  assert.equal(decodeAuthResponse(response, path), response);
});

test("auth decoder rejects malformed nested token and user records", () => {
  assert.throws(() => decodeAuthResponse({ tokens: {}, user: { id: "account" } }, path), InvalidApiPayloadError);
  assert.throws(
    () => decodeAuthResponse({ tokens: { accessToken: "x", accessTokenExpiresAt: "never" }, user: { id: "a" } }, path),
    /accessTokenExpiresAt/,
  );
});

test("health decoder rejects a successful but malformed JSON payload", () => {
  assert.deepEqual(decodeHealthResponse({ status: "ok" }, path), { status: "ok" });
  assert.throws(() => decodeHealthResponse({ status: 200 }, path), /status/);
});

test("leaderboard decoder validates entry fields instead of trusting the generated type", () => {
  const response = {
    biomeId: "forgotten_castle",
    tier: 2,
    seed: 12345,
    playerLevel: 7,
    clientVersion: "0.6.0",
    ruleset: "standard-v1",
    contentVersion: "2026.09.15",
    entries: [{ accountId: "account-id", displayName: "Warden", elapsedSeconds: 82.5, submittedAt: "2026-09-23T00:00:00Z" }],
  };
  assert.equal(decodeLeaderboardResponse(response, path), response);
  assert.throws(() => decodeLeaderboardResponse({ ...response, entries: [{ ...response.entries[0], elapsedSeconds: "fast" }] }, path), /elapsedSeconds/);
  assert.throws(() => decodeLeaderboardResponse({ ...response, tier: 0 }, path), /tier/);
  assert.throws(() => decodeLeaderboardResponse({ ...response, playerLevel: 0 }, path), /playerLevel/);
  assert.throws(() => decodeLeaderboardResponse({ ...response, seed: 0 }, path), /seed/);
});

test("save decoder validates nullable save data and update timestamp", () => {
  assert.deepEqual(decodeSaveResponse({ stateJson: null, updatedAt: "2026-09-23T00:00:00Z" }, path), {
    stateJson: null,
    updatedAt: "2026-09-23T00:00:00Z",
  });
  assert.throws(() => decodeSaveResponse({ stateJson: {}, updatedAt: "bad" }, path), /stateJson/);
});

test("offline backend errors propagate and release the request timer", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { throw new TypeError("Failed to fetch"); };
  try {
    await assert.rejects(request("/api/v1/health", {}, 50, "test", decodeHealthResponse), /Failed to fetch/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("request rejects version mismatch responses and validates successful public payloads", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (_url, options) => {
    assert.equal(options.headers["X-Client-Version"], "test-version");
    return new Response(JSON.stringify({ status: "ok" }), { status: 200 });
  };
  try {
    assert.deepEqual(await request("/api/v1/health", {}, 50, "test-version", decodeHealthResponse), { status: "ok" });
    globalThis.fetch = async () => new Response("{}", { status: 426 });
    await assert.rejects(request("/api/v1/health", {}, 50, "test-version", decodeHealthResponse), VersionMismatchError);
    globalThis.fetch = async () => new Response(JSON.stringify({ status: 42 }), { status: 200 });
    await assert.rejects(request("/api/v1/health", {}, 50, "test-version", decodeHealthResponse), InvalidApiPayloadError);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("leaderboard client sends the selected seed and player-level partition", async () => {
  const originalFetch = globalThis.fetch;
  let requestedUrl = "";
  globalThis.fetch = async (url) => {
    requestedUrl = String(url);
    return new Response(JSON.stringify({
      biomeId: "forgotten_castle",
      tier: 2,
      seed: 98765,
      playerLevel: 12,
      clientVersion: "0.6.0",
      ruleset: "standard-v1",
      contentVersion: "2026.09.15",
      entries: [],
    }), { status: 200 });
  };
  try {
    const result = await getLeaderboards("forgotten_castle", 2, 98765, 12);
    const query = new URL(requestedUrl, "http://localhost").searchParams;
    assert.equal(query.get("seed"), "98765");
    assert.equal(query.get("playerLevel"), "12");
    assert.equal(result.playerLevel, 12);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
