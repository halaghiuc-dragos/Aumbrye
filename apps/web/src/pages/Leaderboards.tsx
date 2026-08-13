import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import { ApiError, getLeaderboards } from "../api/client";
import biomes from "../content/biomes.json";
import { PageHelmet } from "../components/Layout";
import PrerenderReady from "../components/PrerenderReady";

const TIERS = Array.from({ length: 10 }, (_, index) => index + 1);
const MIN_TIER = TIERS[0];
const MAX_TIER = TIERS[TIERS.length - 1];
const DEFAULT_BIOME_ID = biomes[0]?.id ?? "forgotten_castle";
const BIOME_IDS = new Set(biomes.map((biome) => biome.id));

/**
 * URL parameters are user input. `?tier=abc` used to produce NaN, which serializes into the query
 * string literally and guarantees a 400; `?tier=999` queried a tier that cannot exist and rendered
 * a select whose value matched no option.
 */
function parseTier(raw: string | null): number {
  const parsed = Number(raw ?? MIN_TIER);
  if (!Number.isInteger(parsed)) return MIN_TIER;
  return Math.min(MAX_TIER, Math.max(MIN_TIER, parsed));
}

function parseBiomeId(raw: string | null): string {
  return raw && BIOME_IDS.has(raw) ? raw : DEFAULT_BIOME_ID;
}

export default function LeaderboardsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const rawBiomeId = searchParams.get("biomeId");
  const rawTier = searchParams.get("tier");
  const biomeId = parseBiomeId(rawBiomeId);
  const tier = parseTier(rawTier);

  // Canonicalize the URL once when the parsed values differ from what was typed, so shared links
  // and the rendered controls always agree.
  useEffect(() => {
    if (rawBiomeId === biomeId && rawTier === String(tier)) return;
    setSearchParams({ biomeId, tier: String(tier) }, { replace: true });
  }, [rawBiomeId, rawTier, biomeId, tier, setSearchParams]);

  const leaderboardsQuery = useQuery({
    queryKey: ["leaderboards", biomeId, tier],
    queryFn: ({ signal }) => getLeaderboards(biomeId, tier, signal),
    retry: false,
  });

  const entries = leaderboardsQuery.data?.entries ?? [];

  function updateFilters(nextBiomeId: string, nextTier: number) {
    setSearchParams({ biomeId: nextBiomeId, tier: String(nextTier) });
  }

  return (
    <section className="page">
      <PageHelmet
        title="Leaderboards — Aumbrye"
        description="Browse Aumbrye speedrun leaderboards by biome and tier."
        path={`/leaderboards?biomeId=${biomeId}&tier=${tier}`}
      />
      {!leaderboardsQuery.isLoading && <PrerenderReady />}
      <h2>Leaderboards</h2>
      <div className="filters">
        <label>
          Biome
          <select
            value={biomeId}
            onChange={(e) => updateFilters(e.target.value, tier)}
            aria-label="Biome"
          >
            {biomes.map((biome) => (
              <option key={biome.id} value={biome.id}>
                {biome.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          Tier
          <select
            value={tier}
            onChange={(e) => updateFilters(biomeId, Number(e.target.value))}
            aria-label="Tier"
          >
            {TIERS.map((value) => (
              <option key={value} value={value}>
                Tier {value}
              </option>
            ))}
          </select>
        </label>
      </div>

      {leaderboardsQuery.isLoading && (
        <table className="leaderboard" aria-busy="true">
          <caption className="visually-hidden">Leaderboard results</caption>
          <thead>
            <tr>
              <th>#</th>
              <th>Player</th>
              <th>Time</th>
            </tr>
          </thead>
          <tbody>
            {Array.from({ length: 5 }).map((_, index) => (
              <tr key={index} className="skeleton-row">
                <td>
                  <span className="skeleton" />
                </td>
                <td>
                  <span className="skeleton" />
                </td>
                <td>
                  <span className="skeleton" />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {leaderboardsQuery.error && (
        <div className="error-panel">
          <p className="error" role="status">
            {leaderboardsQuery.error instanceof ApiError
              ? leaderboardsQuery.error.detail
              : "Could not load leaderboards. Is the API running?"}
          </p>
          <button type="button" onClick={() => void leaderboardsQuery.refetch()}>
            Retry
          </button>
        </div>
      )}

      {!leaderboardsQuery.isLoading && !leaderboardsQuery.error && (
        <table className="leaderboard">
          <caption className="visually-hidden">Leaderboard results</caption>
          <thead>
            <tr>
              <th>#</th>
              <th>Player</th>
              <th>Time</th>
            </tr>
          </thead>
          <tbody>
            {entries.length === 0 ? (
              <tr>
                <td colSpan={3}>No entries yet</td>
              </tr>
            ) : (
              entries.map((entry, index) => (
                <tr key={`${entry.accountId}-${index}`}>
                  <td>{index + 1}</td>
                  <td>{entry.displayName}</td>
                  <td>{(entry.elapsedSeconds ?? 0).toFixed(1)}s</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      )}
    </section>
  );
}
