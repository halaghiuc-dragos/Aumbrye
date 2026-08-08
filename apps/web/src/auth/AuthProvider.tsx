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

const REFRESH_KEY = "aumbrye_refresh";
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

function storeRefreshToken(token: string | null) {
  if (token) {
    sessionStorage.setItem(REFRESH_KEY, token);
  } else {
    sessionStorage.removeItem(REFRESH_KEY);
  }
}

function clearTokens() {
  sessionStorage.removeItem(REFRESH_KEY);
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
    if (!tokens?.accessToken || !tokens.refreshToken || !tokens.accessTokenExpiresAt) {
      throw new Error("Authentication failed");
    }

    setAccessToken(tokens.accessToken);
    storeRefreshToken(tokens.refreshToken);

    if (refreshTimer.current !== null) {
      window.clearTimeout(refreshTimer.current);
    }
    refreshTimer.current = scheduleRefresh(tokens.accessTokenExpiresAt, async () => {
      const stored = sessionStorage.getItem(REFRESH_KEY);
      if (!stored) return;
      try {
        const next = await refresh(stored);
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
      const stored = sessionStorage.getItem(REFRESH_KEY);
      if (!stored) {
        setAccessToken("");
        return null;
      }
      try {
        const next = await refresh(stored);
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
    const currentRefresh = sessionStorage.getItem(REFRESH_KEY);

    if (refreshTimer.current !== null) {
      window.clearTimeout(refreshTimer.current);
      refreshTimer.current = null;
    }

    setAccessToken("");
    clearTokens();

    if (currentAccess && currentRefresh) {
      try {
        await apiLogout(currentAccess, currentRefresh);
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
    const stored = sessionStorage.getItem(REFRESH_KEY);
    if (!stored) return;
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
