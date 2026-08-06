import { expect, test } from "@playwright/test";

test("smoke journey across primary pages", async ({ page }) => {
  await page.route("**/api/v1/**", async (route) => {
    const url = route.request().url();

    if (url.includes("/auth/register")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          tokens: {
            accessToken: "access-token",
            refreshToken: "refresh-token",
            accessTokenExpiresAt: new Date(Date.now() + 900_000).toISOString(),
          },
          user: { id: "1", email: "hero@aumbrye.test" },
        }),
      });
      return;
    }

    if (url.includes("/saves/current")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          stateJson: JSON.stringify({ character: { name: "Ari", level: 7 } }),
          updatedAt: new Date().toISOString(),
        }),
      });
      return;
    }

    if (url.includes("/leaderboards")) {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          biomeId: "forgotten_castle",
          tier: 1,
          entries: [],
        }),
      });
      return;
    }

    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ status: "ok" }),
    });
  });

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Aumbrye", exact: true })).toBeVisible();

  for (const [label, heading] of [
    ["Account", "Account"],
    ["Patch Notes", "Patch Notes"],
    ["Wiki", "Wiki"],
    ["Leaderboards", "Leaderboards"],
    ["Home", "Aumbrye"],
  ] as const) {
    await page.getByRole("link", { name: label }).click();
    await expect(page.getByRole("heading", { name: heading, exact: heading !== "Aumbrye" })).toBeVisible();
  }

  await page.goto("/wiki/controls");
  await expect(page.getByText(/WASD move/i)).toBeVisible();

  await page.goto("/account");
  await page.getByLabel("Email").fill("hero@aumbrye.test");
  await page.getByLabel("Password").fill("password123");
  await page.getByRole("button", { name: "Register" }).click();
  await expect(page.getByTestId("character-line")).toHaveText("Ari — Level 7");
});
