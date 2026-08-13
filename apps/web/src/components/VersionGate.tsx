import { useEffect } from "react";
import { useAuth } from "../auth/AuthProvider";

/**
 * sessionStorage, not a module-scope flag.
 *
 * A full page reload resets module state, so the old in-memory guard allowed exactly one auto
 * reload *per page load* — meaning a genuinely stale bundle (or a misconfigured expected version)
 * produced an endless reload cycle that never reached the manual UI. Persisting the attempt makes
 * it one auto reload per version incident.
 */
const RELOAD_ATTEMPTED_KEY = "aumbrye_reload_attempted";

/** Clears the guard once the app has successfully talked to the API on this build. */
export function clearVersionReloadGuard() {
  try {
    sessionStorage.removeItem(RELOAD_ATTEMPTED_KEY);
  } catch {
    // Private-mode browsers can throw on storage access; the guard is best-effort.
  }
}

export default function VersionGate() {
  const { versionMismatch } = useAuth();

  useEffect(() => {
    if (!versionMismatch) return;
    try {
      if (sessionStorage.getItem(RELOAD_ATTEMPTED_KEY)) return;
      sessionStorage.setItem(RELOAD_ATTEMPTED_KEY, String(Date.now()));
    } catch {
      // Without storage we cannot prove this is the first attempt, so do not auto-reload at all —
      // the manual button below still works.
      return;
    }
    // Cache-bust the reload so a CDN still serving the stale HTML cannot defeat it.
    const url = new URL(window.location.href);
    url.searchParams.set("v", String(Date.now()));
    window.location.replace(url.toString());
  }, [versionMismatch]);

  if (!versionMismatch) {
    return null;
  }

  return (
    <div className="version-gate" role="alert">
      <p>This page is out of date, please reload.</p>
      <button type="button" onClick={() => window.location.reload()}>
        Reload
      </button>
    </div>
  );
}
