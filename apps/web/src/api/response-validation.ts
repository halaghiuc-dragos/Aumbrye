import type { components } from "./schema";

export class InvalidApiPayloadError extends Error {
  constructor(path: string, detail: string) {
    super(`Invalid API response for ${path}: ${detail}`);
    this.name = "InvalidApiPayloadError";
  }
}

type Decoder<T> = (value: unknown, path: string) => T;

function record(value: unknown, path: string, field: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new InvalidApiPayloadError(path, `${field} must be an object`);
  }
  return value as Record<string, unknown>;
}

function nonEmptyString(value: unknown, path: string, field: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new InvalidApiPayloadError(path, `${field} must be a non-empty string`);
  }
  return value;
}

function isoDate(value: unknown, path: string, field: string): string {
  const date = nonEmptyString(value, path, field);
  if (!Number.isFinite(Date.parse(date))) {
    throw new InvalidApiPayloadError(path, `${field} must be a valid date-time`);
  }
  return date;
}

function decode<T>(path: string, value: unknown, decoder: Decoder<T>): T {
  return decoder(value, path);
}

export function decodeAuthResponse(value: unknown, path: string): components["schemas"]["AuthResponse"] {
  const payload = record(value, path, "response");
  const tokens = record(payload.tokens, path, "tokens");
  const user = record(payload.user, path, "user");
  nonEmptyString(tokens.accessToken, path, "tokens.accessToken");
  if (tokens.refreshToken !== undefined && tokens.refreshToken !== null && typeof tokens.refreshToken !== "string") {
    throw new InvalidApiPayloadError(path, "tokens.refreshToken must be a string or null");
  }
  isoDate(tokens.accessTokenExpiresAt, path, "tokens.accessTokenExpiresAt");
  nonEmptyString(user.id, path, "user.id");
  if (user.email !== undefined && user.email !== null && typeof user.email !== "string") {
    throw new InvalidApiPayloadError(path, "user.email must be a string or null");
  }
  return payload as components["schemas"]["AuthResponse"];
}

export function decodeHealthResponse(value: unknown, path: string): components["schemas"]["HealthResponse"] {
  const payload = record(value, path, "response");
  nonEmptyString(payload.status, path, "status");
  return payload as components["schemas"]["HealthResponse"];
}

export function decodeLeaderboardResponse(
  value: unknown,
  path: string,
): components["schemas"]["LeaderboardPageResponse"] {
  const payload = record(value, path, "response");
  nonEmptyString(payload.biomeId, path, "biomeId");
  if (!Number.isInteger(payload.tier) || Number(payload.tier) < 1) {
    throw new InvalidApiPayloadError(path, "tier must be a positive integer");
  }
  if (!Number.isInteger(payload.playerLevel) || Number(payload.playerLevel) < 1 || Number(payload.playerLevel) > 1000) {
    throw new InvalidApiPayloadError(path, "playerLevel must be an integer between 1 and 1000");
  }
  if (!Number.isInteger(payload.seed) || Number(payload.seed) < 1) {
    throw new InvalidApiPayloadError(path, "seed must be a positive integer");
  }
  nonEmptyString(payload.ruleset, path, "ruleset");
  nonEmptyString(payload.contentVersion, path, "contentVersion");
  nonEmptyString(payload.clientVersion, path, "clientVersion");
  if (!Array.isArray(payload.entries)) {
    throw new InvalidApiPayloadError(path, "entries must be an array");
  }
  payload.entries.forEach((entry, index) => {
    const row = record(entry, path, `entries[${index}]`);
    nonEmptyString(row.accountId, path, `entries[${index}].accountId`);
    if (row.displayName !== null && typeof row.displayName !== "string") {
      throw new InvalidApiPayloadError(path, `entries[${index}].displayName must be a string or null`);
    }
    if (typeof row.elapsedSeconds !== "number" || !Number.isFinite(row.elapsedSeconds) || row.elapsedSeconds < 0) {
      throw new InvalidApiPayloadError(path, `entries[${index}].elapsedSeconds must be a non-negative number`);
    }
    isoDate(row.submittedAt, path, `entries[${index}].submittedAt`);
  });
  return payload as components["schemas"]["LeaderboardPageResponse"];
}

export function decodeSaveResponse(value: unknown, path: string): components["schemas"]["SaveResponse"] {
  const payload = record(value, path, "response");
  if (payload.stateJson !== null && typeof payload.stateJson !== "string") {
    throw new InvalidApiPayloadError(path, "stateJson must be a string or null");
  }
  isoDate(payload.updatedAt, path, "updatedAt");
  return payload as components["schemas"]["SaveResponse"];
}

export const apiResponseDecoders = {
  auth: (value: unknown, path: string) => decode(path, value, decodeAuthResponse),
  health: (value: unknown, path: string) => decode(path, value, decodeHealthResponse),
  leaderboard: (value: unknown, path: string) => decode(path, value, decodeLeaderboardResponse),
  save: (value: unknown, path: string) => decode(path, value, decodeSaveResponse),
};
