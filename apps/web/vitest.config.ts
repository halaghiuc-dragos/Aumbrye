import { configDefaults, defineConfig, mergeConfig } from "vitest/config";
import viteConfig from "./vite.config";

export default defineConfig((configEnv) =>
  mergeConfig(
    viteConfig(configEnv),
    defineConfig({
      test: {
        environment: "jsdom",
        exclude: [...configDefaults.exclude, "e2e/**"],
        setupFiles: ["./src/test/setup.ts"],
        coverage: {
          provider: "v8",
          include: ["src/api/**", "src/auth/**"],
          thresholds: {
            lines: 80,
            functions: 80,
            branches: 80,
            statements: 80,
          },
        },
      },
    }),
  ),
);
