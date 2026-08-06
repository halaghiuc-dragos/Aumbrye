import matter from "gray-matter";

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
  const { data, content } = matter(raw);
  return {
    slug: String(data.slug),
    title: String(data.title),
    body: content.trim(),
  };
}

function parsePatchNote(raw: string): PatchNote {
  const { data, content } = matter(raw);
  const highlights = Array.isArray(data.highlights) ? data.highlights.map(String) : [];
  return {
    slug: String(data.slug ?? data.version),
    version: String(data.version),
    title: String(data.title),
    date: String(data.date),
    highlights,
    body: content.trim(),
  };
}

export const wikiPages: WikiPage[] = Object.values(wikiModules)
  .map(parseWikiPage)
  .sort((a, b) => a.title.localeCompare(b.title));

export const patchNotes: PatchNote[] = Object.values(patchNoteModules)
  .map(parsePatchNote)
  .sort((a, b) => b.version.localeCompare(a.version, undefined, { numeric: true }));

export function getWikiPage(slug: string): WikiPage | undefined {
  return wikiPages.find((page) => page.slug === slug);
}

export function getPatchNote(version: string): PatchNote | undefined {
  return patchNotes.find((entry) => entry.version === version);
}
