import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { describe, expect, it } from "vitest";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { HelmetProvider } from "react-helmet-async";
import { MemoryRouter } from "react-router-dom";
import AccountPage from "./Account";
import { AuthProvider } from "../auth/AuthProvider";
import { server } from "../test/msw";

function renderAccount() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });

  return render(
    <HelmetProvider>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <MemoryRouter>
            <AccountPage />
          </MemoryRouter>
        </AuthProvider>
      </QueryClientProvider>
    </HelmetProvider>,
  );
}

/**
 * The auth form has a mode toggle and a submit button whose label follows the selected mode, so
 * "Log in" / "Register" each match two controls: the toggle first, the submit last.
 */
function lastOf(elements: HTMLElement[]): HTMLElement {
  return elements[elements.length - 1];
}

const authTokens = {
  accessToken: "access-token",
  refreshToken: "refresh-token",
  accessTokenExpiresAt: new Date(Date.now() + 15 * 60_000).toISOString(),
};

describe("AccountPage", () => {
  it("renders character name and level from stateJson", async () => {
    server.use(
      http.post("/api/v1/auth/login", () =>
        HttpResponse.json({ tokens: authTokens, user: { id: "1", email: "hero@aumbrye.test" } }),
      ),
      http.get("/api/v1/saves/current", () =>
        HttpResponse.json({
          stateJson: JSON.stringify({ character: { name: "Ari", level: 7 } }),
          updatedAt: new Date().toISOString(),
        }),
      ),
    );

    const user = userEvent.setup();
    renderAccount();

    await user.type(screen.getByLabelText("Email"), "hero@aumbrye.test");
    await user.type(screen.getByLabelText("Password"), "password123");
    await user.click(lastOf(screen.getAllByRole("button", { name: "Log in" })));

    await waitFor(() => {
      expect(screen.getByTestId("character-line")).toHaveTextContent("Ari — Level 7");
    });
  });

  it("shows session expired on 401 from getSave", async () => {
    server.use(
      http.post("/api/v1/auth/login", () =>
        HttpResponse.json({ tokens: authTokens, user: { id: "1", email: "hero@aumbrye.test" } }),
      ),
      http.get("/api/v1/saves/current", () =>
        HttpResponse.json({ error: "Unauthorized" }, { status: 401 }),
      ),
      http.post("/api/v1/auth/refresh", () =>
        HttpResponse.json({ error: "Unauthorized" }, { status: 401 }),
      ),
    );

    const user = userEvent.setup();
    renderAccount();

    await user.type(screen.getByLabelText("Email"), "hero@aumbrye.test");
    await user.type(screen.getByLabelText("Password"), "password123");
    await user.click(lastOf(screen.getAllByRole("button", { name: "Log in" })));

    await waitFor(() => {
      expect(screen.getByTestId("account-status")).toHaveTextContent(
        "Session expired, please sign in again",
      );
    });
  });

  it("registers and lands on signed-in view without a second submit", async () => {
    server.use(
      http.post("/api/v1/auth/register", () =>
        HttpResponse.json({ tokens: authTokens, user: { id: "1", email: "new@aumbrye.test" } }),
      ),
      http.get("/api/v1/saves/current", () =>
        HttpResponse.json({
          stateJson: JSON.stringify({ character: { name: "Nova", level: 2 } }),
          updatedAt: new Date().toISOString(),
        }),
      ),
    );

    const user = userEvent.setup();
    renderAccount();

    await user.type(screen.getByLabelText("Email"), "new@aumbrye.test");
    await user.type(screen.getByLabelText("Password"), "password123");
    // Switch the form to register mode, then submit it.
    await user.click(screen.getAllByRole("button", { name: "Register" })[0]);
    await user.click(lastOf(screen.getAllByRole("button", { name: "Register" })));

    await waitFor(() => {
      expect(screen.getByText("Registered and signed in.")).toBeInTheDocument();
      expect(screen.getByTestId("character-line")).toHaveTextContent("Nova — Level 2");
    });
  });

  it("sign out clears sessionStorage and returns to the form", async () => {
    server.use(
      http.post("/api/v1/auth/login", () =>
        HttpResponse.json({ tokens: authTokens, user: { id: "1", email: "hero@aumbrye.test" } }),
      ),
      http.get("/api/v1/saves/current", () =>
        HttpResponse.json({
          stateJson: JSON.stringify({ character: { name: "Ari", level: 7 } }),
          updatedAt: new Date().toISOString(),
        }),
      ),
      http.post("/api/v1/auth/logout", () => new HttpResponse(null, { status: 204 })),
    );

    const user = userEvent.setup();
    renderAccount();

    await user.type(screen.getByLabelText("Email"), "hero@aumbrye.test");
    await user.type(screen.getByLabelText("Password"), "password123");
    await user.click(lastOf(screen.getAllByRole("button", { name: "Log in" })));

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Sign out" })).toBeInTheDocument();
    });

    await user.click(screen.getByRole("button", { name: "Sign out" }));

    await waitFor(() => {
      expect(sessionStorage.getItem("aumbrye_refresh")).toBeNull();
      expect(screen.getAllByRole("button", { name: "Log in" }).length).toBeGreaterThan(0);
    });
  });
});
