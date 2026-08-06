import { readFileSync } from "node:fs";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import prerender from "@prerenderer/rollup-plugin";
import PuppeteerRenderer from "@prerenderer/renderer-puppeteer";

const packageJson = JSON.parse(readFileSync(new URL("./package.json", import.meta.url), "utf8")) as {
  version: string;
};

const staticRoutes = ["/", "/account", "/patch-notes", "/wiki", "/leaderboards"];

export default defineConfig(({ mode }) => {
  if (mode === "production" && !process.env.VITE_API_URL) {
    throw new Error("VITE_API_URL is required for production builds.");
  }

  return {
    define: {
      __APP_VERSION__: JSON.stringify(packageJson.version),
    },
    plugins: [react()],
    server: {
      port: 5173,
      strictPort: true,
      proxy:
        mode === "development"
          ? { "/api": { target: "http://localhost:5000", changeOrigin: true } }
          : undefined,
    },
    build: {
      sourcemap: true,
      rollupOptions: {
        plugins: [
          prerender({
            routes: staticRoutes,
            renderer: PuppeteerRenderer,
            rendererOptions: {
              renderAfterTime: 1000,
            },
          }),
        ],
      },
    },
  };
});
