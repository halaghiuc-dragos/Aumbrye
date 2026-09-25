import { parseFrontmatter } from "./frontmatter";
import { findPatchNoteContent, findWikiContent } from "./content-paths";

export type WikiPage = {
  slug: string;
  title: string;
  body: string;
};

export type PatchNote = {
  slug: string;
  version: string;
  title: string;
  date: string;
  highlights: string[];
  body: string;
};

const wikiModules = import.meta.glob("../../content/wiki/*.md", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

const patchNoteModules = import.meta.glob("../../content/patch-notes/*.md", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

function parseWikiPage(raw: string): WikiPage {
  const { data, content } = parseFrontmatter(raw);
  const slug = requiredField(data, "slug");
  const title = requiredField(data, "title");
  return {
    slug,
    title,
    body: content.trim(),
  };
}

function parsePatchNote(raw: string): PatchNote {
  const { data, content } = parseFrontmatter(raw);
  const highlights = Array.isArray(data.highlights) ? data.highlights.map(String) : [];
  const version = requiredField(data, "version");
  const title = requiredField(data, "title");
  const date = requiredField(data, "date");
  return {
    slug: String(data.slug ?? version),
    version,
    title,
    date,
    highlights,
    body: content.trim(),
  };
}

function requiredField(data: Record<string, unknown>, field: string): string {
  const value = data[field];
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error("Invalid content frontmatter: missing " + field);
  }
  return value.trim();
}

/**
 * Numeric semver components, so ordering is by release rather than by string collation.
 *
 * `localeCompare(..., { numeric: true })` only helps within digit runs, so suffixed versions
 * ("0.4.0-hotfix1", "0.10.0-beta") sorted by locale rules and landed in the wrong place.
 * Non-semver slugs sort last and fall back to the date.
 */
function semverKey(version: string): [number, number, number] {
  const match = /^(\d+)\.(\d+)\.(\d+)/.exec(version);
  return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : [0, 0, 0];
}

export const wikiPages: WikiPage[] = Object.values(wikiModules)
  .map(parseWikiPage)
  .sort((a, b) => a.title.localeCompare(b.title));

export const patchNotes: PatchNote[] = Object.values(patchNoteModules)
  .map(parsePatchNote)
  .sort((a, b) => {
    const left = semverKey(a.version);
    const right = semverKey(b.version);
    for (let i = 0; i < 3; i += 1) {
      if (left[i] !== right[i]) return right[i] - left[i];
    }
    return b.date.localeCompare(a.date);
  });

export function getWikiPage(slug: string): WikiPage | undefined {
  return findWikiContent(wikiPages, slug);
}

/**
 * Resolves by slug first, then by version.
 *
 * The list renders `entry.slug` (which may be a custom value), so looking detail pages up by
 * version alone made any custom-slugged note 404 its own list entry.
 */
export function getPatchNote(slugOrVersion: string): PatchNote | undefined {
  return findPatchNoteContent(patchNotes, slugOrVersion);
}
