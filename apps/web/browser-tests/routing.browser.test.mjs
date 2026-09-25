import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import test from "node:test";
import puppeteer from "puppeteer";

const appRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const origin = "http://127.0.0.1:5187";

function launchBrowser() {
  return puppeteer.launch({
    headless: "new",
    executablePath: puppeteer.executablePath(),
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
  });
}

async function waitForServer(process) {
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    if (process.exitCode !== null) throw new Error(`Vite exited early (${process.exitCode})`);
    try {
      const response = await fetch(origin);
      if (response.ok) return;
    } catch {
      // The dev server is still starting.
    }
    await delay(100);
  }
  throw new Error("Vite dev server did not become ready");
}

test("direct wiki/patch routes, missing content, and stale-version reload work in a browser", async () => {
  const vite = spawn(
    process.execPath,
    [resolve(appRoot, "node_modules/vite/bin/vite.js"), "--host", "127.0.0.1", "--port", "5187", "--strictPort"],
    { cwd: appRoot, stdio: "ignore" },
  );
  let browser;
  try {
    await waitForServer(vite);
    browser = await launchBrowser();
    const page = await browser.newPage();

    await page.goto(`${origin}/wiki/controls`, { waitUntil: "networkidle0" });
    assert.equal(await page.$eval("h2", (node) => node.textContent), "Controls");
    assert.equal(await page.$eval('link[rel="canonical"]', (node) => node.href), `${origin}/wiki/controls`);

    await page.goto(`${origin}/patch-notes/0.6.0`, { waitUntil: "networkidle0" });
    assert.match(await page.$eval("h2", (node) => node.textContent), /v0\.6\.0/);
    assert.equal(await page.$eval('link[rel="canonical"]', (node) => node.href), `${origin}/patch-notes/0.6.0`);

    await page.goto(`${origin}/wiki/missing-page`, { waitUntil: "networkidle0" });
    assert.equal(await page.$eval("h2", (node) => node.textContent), "Page not found");

    await page.setRequestInterception(true);
    let staleDocument = "";
    page.on("request", (request) => {
      if (request.isNavigationRequest() && new URL(request.url()).searchParams.has("v") && staleDocument) {
        void request.respond({ status: 200, contentType: "text/html", body: staleDocument });
        return;
      }
      if (request.url().includes("/api/v1/auth/login")) {
        void request.respond({
          status: 426,
          contentType: "application/problem+json",
          body: JSON.stringify({ status: 426, detail: "This page is out of date." }),
        });
      } else {
        void request.continue();
      }
    });
    await page.goto(`${origin}/account?lang=ro`, { waitUntil: "networkidle0" });
    // Model a CDN that serves the exact same cached HTML on the cache-busted request.
    staleDocument = await page.content();
    await page.type('input[type="email"]', "test@example.com");
    await page.type('input[type="password"]', "correct-horse-battery");
    await page.click('button[type="submit"]');
    await page.waitForFunction(() => new URL(location.href).searchParams.has("v"));
    const reloadUrl = new URL(page.url());
    assert.equal(reloadUrl.pathname, "/account");
    assert.equal(reloadUrl.searchParams.get("lang"), "ro");
    assert.ok(reloadUrl.searchParams.get("v"));
  } finally {
    await browser?.close();
    vite.kill("SIGTERM");
  }
});

test("version mismatch still presents manual reload when session storage is denied", async () => {
  const vite = spawn(
    process.execPath,
    [resolve(appRoot, "node_modules/vite/bin/vite.js"), "--host", "127.0.0.1", "--port", "5188", "--strictPort"],
    { cwd: appRoot, stdio: "ignore" },
  );
  let browser;
  try {
    const localOrigin = "http://127.0.0.1:5188";
    const deadline = Date.now() + 20_000;
    while (Date.now() < deadline) {
      try {
        if ((await fetch(localOrigin)).ok) break;
      } catch {
        await delay(100);
      }
    }
    browser = await launchBrowser();
    const page = await browser.newPage();
    await page.evaluateOnNewDocument(() => {
      Object.defineProperty(window, "sessionStorage", { get() { throw new DOMException("denied", "SecurityError"); } });
    });
    await page.setRequestInterception(true);
    page.on("request", (request) => {
      if (request.url().includes("/api/v1/auth/login")) {
        void request.respond({ status: 426, contentType: "application/problem+json", body: "{}" });
      } else {
        void request.continue();
      }
    });
    await page.goto(`${localOrigin}/account`, { waitUntil: "networkidle0" });
    await page.type('input[type="email"]', "test@example.com");
    await page.type('input[type="password"]', "correct-horse-battery");
    await page.click('button[type="submit"]');
    await page.waitForSelector('[role="alert"]');
    assert.equal(new URL(page.url()).searchParams.has("v"), false);
    assert.equal(await page.$eval('[role="alert"] button', (button) => button.textContent), "Reload");
  } finally {
    await browser?.close();
    vite.kill("SIGTERM");
  }
});
