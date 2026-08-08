import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError, request } from "./client";

describe("api client request", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  it("throws ApiError with status and detail on failure", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 400,
        statusText: "Bad Request",
        json: async () => ({ detail: "Invalid email" }),
      }),
    );

    await expect(request("/api/v1/auth/login", { method: "POST" })).rejects.toEqual(
      new ApiError(400, "Invalid email"),
    );
  });

  it("resolves JSON on 200", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        json: async () => ({ status: "ok" }),
      }),
    );

    await expect(request("/api/v1/health")).resolves.toEqual({ status: "ok" });
  });

  it("sends version headers", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({}),
    });
    vi.stubGlobal("fetch", fetchMock);

    await request("/api/v1/health");
    const init = fetchMock.mock.calls[0]?.[1] as RequestInit;
    expect(init.headers).toMatchObject({
      "X-Client-Version": __APP_VERSION__,
      "X-Content-Version": "1",
    });
  });

  it("aborts after the timeout", async () => {
    vi.useFakeTimers();
    vi.stubGlobal(
      "fetch",
      vi.fn(
        (_url: string, init?: RequestInit) =>
          new Promise((_resolve, reject) => {
            init?.signal?.addEventListener("abort", () => {
              reject(new DOMException("Aborted", "AbortError"));
            });
          }),
      ),
    );

    const pending = request("/api/v1/health", {}, 50);
    const assertion = expect(pending).rejects.toThrow();
    await vi.advanceTimersByTimeAsync(60);
    await assertion;
  });
});
