import { FormEvent, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ApiError, getSave } from "../api/client";
import { useAuth } from "../auth/AuthProvider";
import { PageHelmet } from "../components/Layout";

function parseCharacter(stateJson: string | null | undefined): string {
  if (!stateJson) {
    return "";
  }
  try {
    const parsed = JSON.parse(stateJson) as {
      character?: { name?: string; level?: number };
    };
    const name = parsed.character?.name ?? "Wanderer";
    const level = parsed.character?.level ?? 1;
    return `${name} — Level ${level}`;
  } catch {
    return "Save loaded";
  }
}

export default function AccountPage() {
  const { isSignedIn, signIn, signUp, signOut, getAccessToken, refreshAfterUnauthorized } = useAuth();
  const queryClient = useQueryClient();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState("");

  const saveQuery = useQuery({
    queryKey: ["save"],
    enabled: isSignedIn,
    queryFn: async ({ signal }) => {
      const token = await getAccessToken();
      if (!token) {
        throw new ApiError(401, "Session expired, please sign in again");
      }
      try {
        return await getSave(token, signal);
      } catch (error) {
        if (error instanceof ApiError && error.status === 401) {
          const refreshed = await refreshAfterUnauthorized();
          if (!refreshed) {
            throw new ApiError(401, "Session expired, please sign in again");
          }
          return getSave(refreshed, signal);
        }
        throw error;
      }
    },
    retry: false,
  });

  const authMutation = useMutation({
    mutationFn: async ({ mode }: { mode: "login" | "register" }) => {
      if (mode === "login") {
        await signIn(email, password);
      } else {
        await signUp(email, password);
      }
      return mode;
    },
    onSuccess: (mode) => {
      setMessage(mode === "login" ? "Logged in." : "Registered and signed in.");
      void queryClient.invalidateQueries({ queryKey: ["save"] });
    },
    onError: (error: unknown) => {
      if (error instanceof ApiError) {
        setMessage(error.detail);
      }
    },
  });

  async function handleSubmit(e: FormEvent, mode: "login" | "register") {
    e.preventDefault();
    setMessage("");
    authMutation.mutate({ mode });
  }

  async function handleSignOut() {
    await signOut();
    setMessage("Signed out.");
    queryClient.removeQueries({ queryKey: ["save"] });
  }

  const character = parseCharacter(saveQuery.data?.stateJson);
  const sessionExpired =
    saveQuery.error instanceof ApiError && saveQuery.error.status === 401
      ? saveQuery.error.detail
      : "";

  return (
    <section className="page">
      <PageHelmet
        title="Account — Aumbrye"
        description="Sign in to view your Aumbrye character and cloud save summary."
        path="/account"
      />
      <h2>Account</h2>
      {isSignedIn ? (
        <div className="card">
          <p>Signed in.</p>
          {saveQuery.isLoading && <p className="muted">Loading character…</p>}
          {sessionExpired && (
            <p className="error" role="status">
              {sessionExpired}
            </p>
          )}
          {character && <p data-testid="character-line">{character}</p>}
          {saveQuery.error && !sessionExpired && (
            <p className="error" role="status">
              {(saveQuery.error as Error).message}
            </p>
          )}
          <div className="form-actions">
            <button type="button" onClick={() => void saveQuery.refetch()}>
              Refresh character
            </button>
            <button type="button" onClick={() => void handleSignOut()}>
              Sign out
            </button>
          </div>
        </div>
      ) : (
        <form className="card form" onSubmit={(e) => void handleSubmit(e, "login")}>
          <label>
            Email
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="email"
            />
          </label>
          <label>
            Password
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              autoComplete="current-password"
            />
          </label>
          <div className="form-actions">
            <button type="submit" disabled={authMutation.isPending}>
              Log in
            </button>
            <button
              type="button"
              disabled={authMutation.isPending}
              onClick={(e) => void handleSubmit(e, "register")}
            >
              Register
            </button>
          </div>
        </form>
      )}
      {message && (
        <p className="muted" role="status">
          {message}
        </p>
      )}
      <p className="muted">OAuth (Google/Discord) deferred to post-EA — see known issues.</p>
    </section>
  );
}
