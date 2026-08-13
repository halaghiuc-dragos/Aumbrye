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

/**
 * Aborts when either input aborts. Uses `AbortSignal.any` where available and falls back to
 * forwarding the caller's abort into our own controller otherwise.
 */
function combineSignals(timeoutSignal: AbortSignal, callerSignal?: AbortSignal | null): AbortSignal {
  if (!callerSignal) return timeoutSignal;
  if (typeof AbortSignal.any === "function") {
    return AbortSignal.any([timeoutSignal, callerSignal]);
  }
  const controller = new AbortController();
  const forward = (reason: unknown) => controller.abort(reason);
  if (timeoutSignal.aborted || callerSignal.aborted) {
    forward((timeoutSignal.aborted ? timeoutSignal : callerSignal).reason);
  } else {
    timeoutSignal.addEventListener("abort", () => forward(timeoutSignal.reason), { once: true });
    callerSignal.addEventListener("abort", () => forward(callerSignal.reason), { once: true });
  }
  return controller.signal;
}

async function request<T>(
  path: string,
  init: RequestInit = {},
  timeoutMs = 10_000,
  clientVersion = __APP_VERSION__,
): Promise<T> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  // The caller's signal must be COMBINED with the timeout, not chosen over it. react-query always
  // passes a signal, so `init.signal ?? controller.signal` meant every query ran with no timeout
  // at all — a hung backend left them pending until the browser gave up.
  const signal = combineSignals(controller.signal, init.signal);
  try {
    const res = await fetch(`${API_URL}${path}`, {
      ...init,
      signal,
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

/**
 * Opts this client into cookie transport for the refresh token.
 *
 * The server responds with an httpOnly, Secure, SameSite=Strict cookie and omits the refresh token
 * from the JSON body, so no page script — including an injected one — can read it. `credentials:
 * "include"` is required for the browser to store and resend that cookie cross-origin; the backend
 * CORS policy already sets AllowCredentials.
 */
const AUTH_TRANSPORT_HEADERS = { "X-Auth-Transport": "cookie" } as const;

export async function register(email: string, password: string): Promise<AuthResponse> {
  const body: PostBody<"/api/v1/auth/register", "post"> = { email, password };
  return request<AuthResponse>("/api/v1/auth/register", {
    method: "POST",
    headers: AUTH_TRANSPORT_HEADERS,
    credentials: "include",
    body: JSON.stringify(body),
  });
}

export async function login(email: string, password: string): Promise<AuthResponse> {
  const body: PostBody<"/api/v1/auth/login", "post"> = { email, password };
  return request<AuthResponse>("/api/v1/auth/login", {
    method: "POST",
    headers: AUTH_TRANSPORT_HEADERS,
    credentials: "include",
    body: JSON.stringify(body),
  });
}

/** Sends an empty body — the server reads the refresh token from the httpOnly cookie. */
export async function refresh(): Promise<AuthResponse> {
  return request<AuthResponse>("/api/v1/auth/refresh", {
    method: "POST",
    headers: AUTH_TRANSPORT_HEADERS,
    credentials: "include",
    body: JSON.stringify({}),
  });
}

export async function logout(accessToken: string): Promise<void> {
  await request<void>("/api/v1/auth/logout", {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, ...AUTH_TRANSPORT_HEADERS },
    credentials: "include",
    body: JSON.stringify({}),
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
