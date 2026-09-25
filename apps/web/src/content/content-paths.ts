export type SluggedContent = { slug: string };
export type PatchNoteContent = SluggedContent & { version: string };

function validSegment(segment: string): boolean {
  if (
    segment.length === 0 ||
    segment !== segment.trim() ||
    segment === "." ||
    segment === ".." ||
    segment.includes("/") ||
    segment.includes("\\")
  ) {
    return false;
  }
  for (const character of segment) {
    const code = character.charCodeAt(0);
    if (code < 0x20 || code === 0x7f) return false;
  }
  return true;
}

export function wikiContentPath(slug: string): string | undefined {
  if (!validSegment(slug)) return undefined;
  return `/wiki/${encodeURIComponent(slug)}`;
}

export function patchNoteContentPath(slug: string): string | undefined {
  if (!validSegment(slug)) return undefined;
  return `/patch-notes/${encodeURIComponent(slug)}`;
}

export function findWikiContent<T extends SluggedContent>(
  pages: readonly T[],
  routeSlug: string,
): T | undefined {
  if (!validSegment(routeSlug)) return undefined;
  return pages.find((page) => page.slug === routeSlug);
}

export function findPatchNoteContent<T extends PatchNoteContent>(
  notes: readonly T[],
  routeSlugOrVersion: string,
): T | undefined {
  if (!validSegment(routeSlugOrVersion)) return undefined;
  return (
    notes.find((entry) => entry.slug === routeSlugOrVersion) ??
    notes.find((entry) => entry.version === routeSlugOrVersion)
  );
}
