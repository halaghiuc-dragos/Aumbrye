const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:5000";

export type AuthTokens = {
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
};

export async function register(email: string, password: string) {
  const res = await fetch(`${API_URL}/api/v1/auth/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  return res.json();
}

export async function login(email: string, password: string) {
  const res = await fetch(`${API_URL}/api/v1/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  return res.json();
}

export async function getLeaderboards(biomeId: string, tier = 1) {
  const params = new URLSearchParams({ biomeId, tier: String(tier) });
  const res = await fetch(`${API_URL}/api/v1/leaderboards?${params}`);
  return res.json();
}

export async function getSave(accessToken: string) {
  const res = await fetch(`${API_URL}/api/v1/saves/current`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  return res.json();
}
