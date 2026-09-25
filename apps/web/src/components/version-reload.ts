export const RELOAD_ATTEMPTED_KEY = "aumbrye_reload_attempted";

export type SessionStorageLike = Pick<Storage, "getItem" | "setItem" | "removeItem">;

export function cacheBustVersionReloadUrl(href: string, timestamp: number): string {
  const url = new URL(href);
  url.searchParams.set("v", String(timestamp));
  return url.toString();
}

/** Returns a cache-busted reload URL once per session; storage denial fails closed. */
export function beginVersionReload(
  storage: SessionStorageLike | (() => SessionStorageLike) | null | undefined,
  href: string,
  timestamp: number,
): string | undefined {
  if (!storage) return undefined;
  try {
    const session = typeof storage === "function" ? storage() : storage;
    if (session.getItem(RELOAD_ATTEMPTED_KEY)) return undefined;
    session.setItem(RELOAD_ATTEMPTED_KEY, String(timestamp));
    return cacheBustVersionReloadUrl(href, timestamp);
  } catch {
    return undefined;
  }
}

export function clearVersionReloadAttempt(
  storage: SessionStorageLike | (() => SessionStorageLike) | null | undefined,
): void {
  try {
    if (storage) (typeof storage === "function" ? storage() : storage).removeItem(RELOAD_ATTEMPTED_KEY);
  } catch {
    // Private-mode browsers can deny storage; a successful API request remains non-fatal.
  }
}
