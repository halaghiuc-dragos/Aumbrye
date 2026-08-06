import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { HelmetProvider } from "react-helmet-async";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import LeaderboardsPage from "./Leaderboards";
import { server } from "../test/msw";

function renderLeaderboards(path = "/leaderboards?biomeId=forgotten_castle&tier=1") {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <HelmetProvider>
      <QueryClientProvider client={queryClient}>
        <MemoryRouter initialEntries={[path]}>
          <Routes>
            <Route path="/leaderboards" element={<LeaderboardsPage />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>
    </HelmetProvider>,
  );
}

describe("LeaderboardsPage", () => {
  it("shows skeleton then rows", async () => {
    server.use(
      http.get("/api/v1/leaderboards", async () => {
        await new Promise((resolve) => setTimeout(resolve, 20));
        return HttpResponse.json({
          biomeId: "forgotten_castle",
          tier: 1,
          entries: [{ accountId: "1", displayName: "Runner", elapsedSeconds: 42.5 }],
        });
      }),
    );

    renderLeaderboards();

    expect(screen.getByRole("table", { busy: true })).toBeInTheDocument();

    await waitFor(() => {
      expect(screen.getByText("Runner")).toBeInTheDocument();
    });
  });

  it("renders error with retry on 500", async () => {
    server.use(
      http.get("/api/v1/leaderboards", () =>
        HttpResponse.json({ detail: "Server error" }, { status: 500 }),
      ),
    );

    renderLeaderboards();

    await waitFor(() => {
      expect(screen.getByRole("status")).toHaveTextContent("Server error");
      expect(screen.getByRole("button", { name: "Retry" })).toBeInTheDocument();
    });
  });

  it('renders "No entries yet" for an empty list', async () => {
    server.use(
      http.get("/api/v1/leaderboards", () =>
        HttpResponse.json({ biomeId: "forgotten_castle", tier: 1, entries: [] }),
      ),
    );

    renderLeaderboards();

    await waitFor(() => {
      expect(screen.getByText("No entries yet")).toBeInTheDocument();
    });
  });

  it("updates query string and refetches when biome changes", async () => {
    let requestedBiome = "";

    server.use(
      http.get("/api/v1/leaderboards", ({ request }) => {
        const url = new URL(request.url);
        requestedBiome = url.searchParams.get("biomeId") ?? "";
        return HttpResponse.json({
          biomeId: requestedBiome,
          tier: 1,
          entries: [{ accountId: "1", displayName: requestedBiome, elapsedSeconds: 10 }],
        });
      }),
    );

    const user = userEvent.setup();
    renderLeaderboards();

    await waitFor(() => {
      expect(screen.getByText("forgotten_castle")).toBeInTheDocument();
    });

    await user.selectOptions(screen.getByLabelText("Biome"), "crystal_caverns");

    await waitFor(() => {
      expect(requestedBiome).toBe("crystal_caverns");
      expect(screen.getByText("crystal_caverns")).toBeInTheDocument();
    });
  });
});
