import { Buffer } from "buffer";

/**
 * `gray-matter`'s YAML engine (js-yaml) references the Node `Buffer` global
 * when resolving scalar types, even for plain-text frontmatter. Browsers
 * don't provide one, so it must be polyfilled before any module that parses
 * content (see `src/content/loader.ts`) runs. Import this module first,
 * ahead of any other application import.
 */
declare global {
  interface Window {
    Buffer: typeof Buffer;
  }
}

if (typeof window !== "undefined" && !window.Buffer) {
  window.Buffer = Buffer;
}
