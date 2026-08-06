import { render, screen, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { HelmetProvider } from "react-helmet-async";
import { AuthProvider, useAuth } from "./AuthProvider";
import { server } from "../test/msw";

function TestConsumer() {
  const { isSignedIn } = useAuth();
  return <div data-testid="signed-in">{String(isSignedIn)}</div>;
}

describe("AuthProvider", () => {
  beforeEach(() => {
    sessionStorage.clear();
    localStorage.clear();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("refreshes 60 seconds before expiry using fake timers", async () => {
    server.use(
      http.post("/api/v1/auth/refresh", () =>
        HttpResponse.json({
          tokens: {
            accessToken: "next-access",
            refreshToken: "next-refresh",
            accessTokenExpiresAt: new Date(Date.now() + 120_000).toISOString(),
          },
        }),
      ),
    );

    sessionStorage.setItem("aumbrye_refresh", "stored-refresh");
    vi.useFakeTimers({ shouldAdvanceTime: true });

    render(
      <HelmetProvider>
        <QueryClientProvider client={new QueryClient()}>
          <AuthProvider>
            <TestConsumer />
          </AuthProvider>
        </QueryClientProvider>
      </HelmetProvider>,
    );

    await waitFor(() => {
      expect(screen.getByTestId("signed-in")).toHaveTextContent("true");
    });

    await vi.advanceTimersByTimeAsync(61_000);

    await waitFor(() => {
      expect(sessionStorage.getItem("aumbrye_refresh")).toBe("next-refresh");
    });
  });

  it("signs out when refresh fails", async () => {
    sessionStorage.setItem("aumbrye_refresh", "stored-refresh");

    server.use(
      http.post("/api/v1/auth/refresh", () =>
        HttpResponse.json({ error: "Unauthorized" }, { status: 401 }),
      ),
    );

    render(
      <HelmetProvider>
        <QueryClientProvider client={new QueryClient()}>
          <AuthProvider>
            <TestConsumer />
          </AuthProvider>
        </QueryClientProvider>
      </HelmetProvider>,
    );

    await waitFor(() => {
      expect(screen.getByTestId("signed-in")).toHaveTextContent("false");
      expect(sessionStorage.getItem("aumbrye_refresh")).toBeNull();
    });
  });
});
