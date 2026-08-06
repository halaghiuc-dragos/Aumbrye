import { expect, test } from "@playwright/test";

const apiUrl = process.env.PLAYWRIGHT_API_URL ?? "http://localhost:5000";

test.describe("integration", () => {
  test("health", async ({ page }) => {
    const response = await page.request.get(`${apiUrl}/api/v1/health`, {
      headers: { Origin: "http://localhost:4173" },
    });
    expect(response.ok()).toBeTruthy();
    const allowOrigin = response.headers()["access-control-allow-origin"];
    expect(allowOrigin).toBeTruthy();
  });

  test("register and sign in", async ({ page }) => {
    const email = `e2e_${Date.now()}@test.local`;
    await page.goto("/account");
    await page.getByLabel("Email").fill(email);
    await page.getByLabel("Password").fill("password123");
    await page.getByRole("button", { name: "Register" }).click();
    await expect(page.getByText("Registered and signed in.")).toBeVisible();
    await expect(page.getByTestId("character-line")).toHaveText("Wanderer — Level 1");
  });

  test("session survives expiry", async ({ page }) => {
    test.setTimeout(120_000);
    const email = `session_${Date.now()}@test.local`;
    await page.goto("/account");
    await page.getByLabel("Email").fill(email);
    await page.getByLabel("Password").fill("password123");
    await page.getByRole("button", { name: "Register" }).click();
    await expect(page.getByText("Signed in.")).toBeVisible();
    await page.waitForTimeout(90_000);
    await expect(page.getByText("Signed in.")).toBeVisible();
  });

  test("leaderboards empty", async ({ page }) => {
    await page.goto("/leaderboards");
    await expect(page.getByText("No entries yet")).toBeVisible();
    await expect(page.locator(".error")).toHaveCount(0);
  });

  test("leaderboards populated", async ({ request, page }) => {
    const email = `lb_${Date.now()}@test.local`;
    const headers = {
      "X-Client-Version": "0.3.0",
      "X-Content-Version": "1",
    };

    const register = await request.post(`${apiUrl}/api/v1/auth/register`, {
      data: { email, password: "password123" },
      headers,
    });
    expect(register.ok()).toBeTruthy();
    const auth = (await register.json()) as { tokens: { accessToken: string } };
    const token = auth.tokens.accessToken;
    const authHeaders = { ...headers, Authorization: `Bearer ${token}` };

    const createRun = await request.post(`${apiUrl}/api/v1/runs`, {
      data: { biomeId: "forgotten_castle", seed: 42, tier: 1 },
      headers: authHeaders,
    });
    expect(createRun.ok()).toBeTruthy();
    const run = (await createRun.json()) as { runId: string };

    const complete = await request.post(`${apiUrl}/api/v1/runs/${run.runId}/complete`, {
      data: {
        outcome: "escaped",
        elapsedSeconds: 42.5,
        bossDefeated: true,
        lootClaimedInstanceIds: [],
      },
      headers: authHeaders,
    });
    expect(complete.ok()).toBeTruthy();

    const submit = await request.post(`${apiUrl}/api/v1/leaderboards/submit`, {
      data: { runId: run.runId, optIn: true },
      headers: authHeaders,
    });
    expect(submit.ok()).toBeTruthy();

    await page.goto("/leaderboards?biomeId=forgotten_castle&tier=1");
    await expect(page.getByRole("cell", { name: "42.5s" })).toBeVisible();
  });

  test("version gate", async ({ page }) => {
    await page.route("**/api/v1/**", async (route) => {
      const headers = {
        ...route.request().headers(),
        "x-client-version": "0.0.1",
      };
      await route.continue({ headers });
    });
    await page.goto("/account");
    await page.getByLabel("Email").fill("version@test.local");
    await page.getByLabel("Password").fill("password123");
    await page.getByRole("button", { name: "Log in" }).click();
    await expect(page.getByRole("alert")).toContainText("out of date");
  });

  test("deep link", async ({ page }) => {
    await page.goto("/wiki/controls");
    await expect(page.getByText("WASD move, mouse look")).toBeVisible();
  });
});
