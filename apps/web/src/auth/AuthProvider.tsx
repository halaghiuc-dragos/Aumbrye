import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { ApiError, logout as apiLogout, login, refresh, register, type AuthResponse } from "../api/client";
import { clearVersionReloadGuard } from "../components/VersionGate";

/** Marker only — never a credential. See markSessionPresent(). */
const SESSION_MARKER_KEY = "aumbrye_session";
const LEGACY_REFRESH_KEY = "aumbrye_refresh";
const LEGACY_TOKEN_KEY = "aumbrye_token";

type AuthContextValue = {
  accessToken: string;
  isSignedIn: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  getAccessToken: () => Promise<string | null>;
  refreshAfterUnauthorized: () => Promise<string | null>;
  versionMismatch: boolean;
};

const AuthContext = createContext<AuthContextValue | null>(null);

/**
 * The refresh token now lives in an httpOnly cookie the page cannot read, so all we keep locally
 * is a non-sensitive marker saying "a session cookie should exist". It exists purely so a cold
 * boot knows whether attempting a silent refresh is worthwhile; losing it costs a redundant 401,
 * never a session.
 */
function markSessionPresent(present: boolean) {
  if (present) {
    localStorage.setItem(SESSION_MARKER_KEY, "1");
  } else {
    localStorage.removeItem(SESSION_MARKER_KEY);
  }
}

function hasSessionMarker(): boolean {
  return localStorage.getItem(SESSION_MARKER_KEY) === "1";
}

function clearTokens() {
  markSessionPresent(false);
  // Remove credentials written by earlier builds, which kept the refresh token where any XSS
  // payload could read it.
  sessionStorage.removeItem(LEGACY_REFRESH_KEY);
  localStorage.removeItem(LEGACY_TOKEN_KEY);
}

function scheduleRefresh(expiresAt: string, refreshFn: () => Promise<void>) {
  const msUntilExpiry = new Date(expiresAt).getTime() - Date.now();
  const delay = Math.max(0, msUntilExpiry - 60_000);
  return window.setTimeout(() => {
    void refreshFn();
  }, delay);
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [accessToken, setAccessToken] = useState("");
  const [versionMismatch, setVersionMismatch] = useState(false);
  const refreshTimer = useRef<number | null>(null);
  const refreshPromise = useRef<Promise<string | null> | null>(null);

  const applyAuth = useCallback(function applyAuth(auth: AuthResponse) {
    const tokens = auth.tokens;
    // refreshToken is deliberately absent under cookie transport — the server keeps it in an
    // httpOnly cookie — so its absence must not be treated as a failed authentication.
    if (!tokens?.accessToken || !tokens.accessTokenExpiresAt) {
      throw new Error("Authentication failed");
    }

    // A successful exchange with the API proves this bundle is current, so the version-mismatch
    // auto-reload guard can be released for the next incident.
    clearVersionReloadGuard();
    setAccessToken(tokens.accessToken);
    markSessionPresent(true);

    if (refreshTimer.current !== null) {
      window.clearTimeout(refreshTimer.current);
    }
    refreshTimer.current = scheduleRefresh(tokens.accessTokenExpiresAt, async () => {
      try {
        const next = await refresh();
        applyAuth(next);
      } catch (err) {
        if (err instanceof ApiError && err.status === 401) {
          clearTokens();
          setAccessToken("");
        }
      }
    });
  }, []);

  const refreshSession = useCallback(async (): Promise<string | null> => {
    if (refreshPromise.current) {
      return refreshPromise.current;
    }

    const promise = (async () => {
      try {
        const next = await refresh();
        applyAuth(next);
        return next.tokens?.accessToken ?? null;
      } catch {
        clearTokens();
        setAccessToken("");
        return null;
      } finally {
        refreshPromise.current = null;
      }
    })();

    refreshPromise.current = promise;
    return promise;
  }, [applyAuth]);

  const signOut = useCallback(async () => {
    const currentAccess = accessToken;

    if (refreshTimer.current !== null) {
      window.clearTimeout(refreshTimer.current);
      refreshTimer.current = null;
    }

    setAccessToken("");
    clearTokens();

    if (currentAccess) {
      try {
        // Clears the httpOnly cookie server-side; the browser cannot do it from here.
        await apiLogout(currentAccess);
      } catch {
        // Local session is cleared even when logout is unavailable.
      }
    }
  }, [accessToken]);

  const signIn = useCallback(
    async (email: string, password: string) => {
      try {
        const auth = await login(email, password);
        applyAuth(auth);
      } catch (err) {
        if (err instanceof ApiError && err.status === 426) {
          setVersionMismatch(true);
        }
        throw err;
      }
    },
    [applyAuth],
  );

  const signUp = useCallback(
    async (email: string, password: string) => {
      try {
        const auth = await register(email, password);
        applyAuth(auth);
      } catch (err) {
        if (err instanceof ApiError && err.status === 426) {
          setVersionMismatch(true);
        }
        throw err;
      }
    },
    [applyAuth],
  );

  const getAccessToken = useCallback(async () => {
    if (accessToken) {
      return accessToken;
    }
    return refreshSession();
  }, [accessToken, refreshSession]);

  const refreshAfterUnauthorized = useCallback(async () => {
    setAccessToken("");
    return refreshSession();
  }, [refreshSession]);

  useEffect(() => {
    localStorage.removeItem(LEGACY_TOKEN_KEY);
    sessionStorage.removeItem(LEGACY_REFRESH_KEY);
    if (!hasSessionMarker()) return;
    void refreshSession();
    return () => {
      if (refreshTimer.current !== null) {
        window.clearTimeout(refreshTimer.current);
      }
    };
  }, [refreshSession]);

  const value = useMemo(
    () => ({
      accessToken,
      isSignedIn: accessToken.length > 0,
      signIn,
      signUp,
      signOut,
      getAccessToken,
      refreshAfterUnauthorized,
      versionMismatch,
    }),
    [accessToken, getAccessToken, refreshAfterUnauthorized, signIn, signUp, signOut, versionMismatch],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error("useAuth must be used within AuthProvider");
  }
  return ctx;
}
