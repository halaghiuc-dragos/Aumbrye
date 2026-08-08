import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterAll, afterEach, beforeAll } from "vitest";
import { server } from "./msw";

beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterEach(() => cleanup());
afterAll(() => server.close());
