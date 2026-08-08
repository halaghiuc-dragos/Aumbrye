import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { HelmetProvider } from "react-helmet-async";
import Layout from "./components/Layout";
import NotFound from "./components/NotFound";
import AccountPage from "./pages/Account";
import LandingPage from "./pages/Landing";
import LeaderboardsPage from "./pages/Leaderboards";
import PatchNotesPage from "./pages/PatchNotes";
import WikiIndexPage from "./pages/Wiki";
import { AuthProvider } from "./auth/AuthProvider";

function renderAt(path: string) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <HelmetProvider>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <MemoryRouter initialEntries={[path]}>
            <Routes>
              <Route element={<Layout />}>
                <Route index element={<LandingPage />} />
                <Route path="account" element={<AccountPage />} />
                <Route path="patch-notes" element={<PatchNotesPage />} />
                <Route path="wiki" element={<WikiIndexPage />} />
                <Route path="leaderboards" element={<LeaderboardsPage />} />
                <Route path="*" element={<NotFound />} />
              </Route>
            </Routes>
          </MemoryRouter>
        </AuthProvider>
      </QueryClientProvider>
    </HelmetProvider>,
  );
}

describe("App routing", () => {
  it("routes nav links and sets aria-current", async () => {
    const user = userEvent.setup();
    renderAt("/");

    await user.click(screen.getByRole("link", { name: "Account" }));
    expect(screen.getByRole("heading", { name: "Account" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Account" })).toHaveAttribute("aria-current", "page");

    await user.click(screen.getByRole("link", { name: "Leaderboards" }));
    expect(screen.getByRole("heading", { name: "Leaderboards" })).toBeInTheDocument();
  });

  it("renders NotFound for unknown paths", () => {
    renderAt("/does-not-exist");
    expect(screen.getByRole("heading", { name: "Page not found" })).toBeInTheDocument();
  });
});
