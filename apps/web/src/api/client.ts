import type { components, paths } from "./schema";

const API_URL = import.meta.env.VITE_API_URL ?? (import.meta.env.DEV ? "" : undefined);
if (API_URL === undefined) {
  throw new Error("VITE_API_URL must be set for production builds.");
}

const CONTENT_VERSION = "1";

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly detail: string,
  ) {
    super(detail);
    this.name = "ApiError";
  }
}

export class VersionMismatchError extends ApiError {
  constructor() {
    super(426, "This page is out of date, please reload.");
    this.name = "VersionMismatchError";
  }
}

type PostBody<P extends keyof paths, M extends keyof paths[P]> = paths[P][M] extends {
  requestBody: { content: { "application/json": infer B } };
}
  ? B
  : never;

async function request<T>(
  path: string,
  init: RequestInit = {},
  timeoutMs = 10_000,
  clientVersion = __APP_VERSION__,
): Promise<T> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`${API_URL}${path}`, {
      ...init,
      signal: init.signal ?? controller.signal,
      headers: {
        "Content-Type": "application/json",
        "X-Client-Version": clientVersion,
        "X-Content-Version": CONTENT_VERSION,
        ...init.headers,
      },
    });
    if (res.status === 426) {
      throw new VersionMismatchError();
    }
    if (!res.ok) {
      const problem = (await res.json().catch(() => ({}))) as {
        detail?: string;
        error?: string;
      };
      throw new ApiError(res.status, problem.detail ?? problem.error ?? res.statusText);
    }
    return res.status === 204 ? (undefined as T) : ((await res.json()) as T);
  } finally {
    clearTimeout(timer);
  }
}

export type AuthResponse = components["schemas"]["AuthResponse"];
export type SaveResponse = components["schemas"]["SaveResponse"];
export type LeaderboardPageResponse = components["schemas"]["LeaderboardPageResponse"];

export async function register(email: string, password: string): Promise<AuthResponse> {
  const body: PostBody<"/api/v1/auth/register", "post"> = { email, password };
  return request<AuthResponse>("/api/v1/auth/register", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export async function login(email: string, password: string): Promise<AuthResponse> {
  const body: PostBody<"/api/v1/auth/login", "post"> = { email, password };
  return request<AuthResponse>("/api/v1/auth/login", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export async function refresh(refreshToken: string): Promise<AuthResponse> {
  const body: PostBody<"/api/v1/auth/refresh", "post"> = { refreshToken };
  return request<AuthResponse>("/api/v1/auth/refresh", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

export async function logout(accessToken: string, refreshToken: string): Promise<void> {
  const body: PostBody<"/api/v1/auth/logout", "post"> = { refreshToken };
  await request<void>("/api/v1/auth/logout", {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}` },
    body: JSON.stringify(body),
  });
}

export async function getLeaderboards(
  biomeId: string,
  tier = 1,
  signal?: AbortSignal,
): Promise<LeaderboardPageResponse> {
  const params = new URLSearchParams({ biomeId, tier: String(tier) });
  return request<LeaderboardPageResponse>(`/api/v1/leaderboards?${params}`, { signal });
}

export async function getSave(accessToken: string, signal?: AbortSignal): Promise<SaveResponse> {
  return request<SaveResponse>("/api/v1/saves/current", {
    headers: { Authorization: `Bearer ${accessToken}` },
    signal,
  });
}

export async function healthCheck(): Promise<components["schemas"]["HealthResponse"]> {
  return request("/api/v1/health");
}

export { request };
