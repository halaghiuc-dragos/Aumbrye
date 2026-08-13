/**
 * Minimal frontmatter parser for this repo's own Markdown.
 *
 * This replaces `gray-matter`, which pulled in js-yaml plus a `Buffer` polyfill — roughly
 * 70–100 KB shipped to every visitor, and a Node global leaked into the page, to split `---`
 * blocks off a handful of local files whose frontmatter we author ourselves.
 *
 * Deliberately supports only what that frontmatter uses:
 *   - `key: value` scalars, with optional surrounding single or double quotes
 *   - block sequences (`key:` followed by indented `- item` lines)
 *   - inline sequences (`key: [a, b]`)
 *
 * Anything else (nested maps, multi-line scalars, anchors) is out of scope on purpose. If a
 * document ever needs them, bring back a real YAML parser rather than growing this.
 */

export type FrontmatterData = Record<string, string | string[]>;

export type ParsedDocument = {
  data: FrontmatterData;
  content: string;
};

const FRONTMATTER_RE = /^---\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/;
const KEY_RE = /^([A-Za-z_][\w-]*):[ \t]*(.*)$/;
const SEQUENCE_ITEM_RE = /^[ \t]+-[ \t]+(.*)$/;

function unquote(raw: string): string {
  const value = raw.trim();
  if (value.length >= 2) {
    const first = value[0];
    const last = value[value.length - 1];
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return value.slice(1, -1);
    }
  }
  return value;
}

function parseInlineSequence(raw: string): string[] {
  const inner = raw.slice(1, -1).trim();
  if (inner === "") return [];
  return inner.split(",").map(unquote);
}

export function parseFrontmatter(raw: string): ParsedDocument {
  const match = FRONTMATTER_RE.exec(raw);
  if (!match) {
    return { data: {}, content: raw };
  }

  const data: FrontmatterData = {};
  const lines = match[1].split(/\r?\n/);
  let currentKey: string | null = null;

  for (const line of lines) {
    if (line.trim() === "" || line.trimStart().startsWith("#")) continue;

    const item = SEQUENCE_ITEM_RE.exec(line);
    if (item && currentKey) {
      const existing = data[currentKey];
      if (Array.isArray(existing)) {
        existing.push(unquote(item[1]));
      } else {
        data[currentKey] = [unquote(item[1])];
      }
      continue;
    }

    const keyMatch = KEY_RE.exec(line);
    if (!keyMatch) continue;

    const [, key, rest] = keyMatch;
    currentKey = key;
    const value = rest.trim();

    if (value === "") {
      // A bare `key:` opens a block sequence; the items follow on indented lines. Seed an empty
      // array so a sequence with no items still reads as an array rather than a missing key.
      data[key] = [];
    } else if (value.startsWith("[") && value.endsWith("]")) {
      data[key] = parseInlineSequence(value);
    } else {
      data[key] = unquote(value);
    }
  }

  return { data, content: raw.slice(match[0].length) };
}
