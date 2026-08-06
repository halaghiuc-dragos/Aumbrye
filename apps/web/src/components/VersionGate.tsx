import { useEffect } from "react";
import { useAuth } from "../auth/AuthProvider";

let reloadAttempted = false;

export default function VersionGate() {
  const { versionMismatch } = useAuth();

  useEffect(() => {
    if (versionMismatch && !reloadAttempted) {
      reloadAttempted = true;
      window.location.reload();
    }
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
