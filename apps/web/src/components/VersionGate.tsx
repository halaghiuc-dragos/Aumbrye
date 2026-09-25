import { useEffect } from "react";
import { useAuth } from "../auth/AuthProvider";
import { beginVersionReload, clearVersionReloadAttempt } from "./version-reload";

/**
 * sessionStorage, not a module-scope flag.
 *
 * A full page reload resets module state, so the old in-memory guard allowed exactly one auto
 * reload *per page load* — meaning a genuinely stale bundle (or a misconfigured expected version)
 * produced an endless reload cycle that never reached the manual UI. Persisting the attempt makes
 * it one auto reload per version incident.
 */
/** Clears the guard once the app has successfully talked to the API on this build. */
export function clearVersionReloadGuard() {
  clearVersionReloadAttempt(() => sessionStorage);
}

export default function VersionGate() {
  const { versionMismatch } = useAuth();

  useEffect(() => {
    if (!versionMismatch) return;
    // Without storage we cannot prove this is the first attempt, so leave the manual reload UI.
    const reloadUrl = beginVersionReload(() => sessionStorage, window.location.href, Date.now());
    if (reloadUrl) window.location.replace(reloadUrl);
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
