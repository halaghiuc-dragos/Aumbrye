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
    let refreshCalls = 0;
    server.use(
      http.post("/api/v1/auth/refresh", () => {
        refreshCalls += 1;
        return HttpResponse.json({
          tokens: {
            accessToken: "next-access",
            refreshToken: "next-refresh",
            accessTokenExpiresAt: new Date(Date.now() + 120_000).toISOString(),
          },
        });
      }),
    );

    localStorage.setItem("aumbrye_session", "1");
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

    // The refresh token is never visible to the page under cookie transport, so assert on the
    // observable outcome: the pre-expiry timer fired and the session is still signed in.
    await waitFor(() => {
      expect(refreshCalls).toBeGreaterThanOrEqual(2);
      expect(screen.getByTestId("signed-in")).toHaveTextContent("true");
    });
  });

  it("signs out when refresh fails", async () => {
    localStorage.setItem("aumbrye_session", "1");

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
      expect(localStorage.getItem("aumbrye_session")).toBeNull();
    });
  });
});
