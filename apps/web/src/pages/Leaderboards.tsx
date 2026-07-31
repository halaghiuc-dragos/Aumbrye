import { useEffect, useState } from "react";
import { getLeaderboards } from "../api/client";

const BIOMES = [
  { id: "forgotten_castle", label: "Forgotten Castle" },
  { id: "crystal_caverns", label: "Crystal Caverns" },
  { id: "poison_swamp", label: "Poison Swamp" },
  { id: "frozen_fortress", label: "Frozen Fortress" },
  { id: "dark_cathedral", label: "Dark Cathedral" },
];

type Entry = {
  accountId: string;
  displayName: string;
  elapsedSeconds: number;
  submittedAt: string;
};

export default function LeaderboardsPage() {
  const [biomeId, setBiomeId] = useState("forgotten_castle");
  const [tier, setTier] = useState(1);
  const [entries, setEntries] = useState<Entry[]>([]);
  const [error, setError] = useState("");

  useEffect(() => {
    getLeaderboards(biomeId, tier)
      .then((data) => {
        setEntries(data.entries ?? []);
        setError("");
      })
      .catch(() => setError("Could not load leaderboards. Is the API running?"));
  }, [biomeId, tier]);

  return (
    <section className="page">
      <h2>Leaderboards</h2>
      <div className="filters">
        <select value={biomeId} onChange={(e) => setBiomeId(e.target.value)}>
          {BIOMES.map((b) => (
            <option key={b.id} value={b.id}>
              {b.label}
            </option>
          ))}
        </select>
        <select value={tier} onChange={(e) => setTier(Number(e.target.value))}>
          {[1, 2, 3, 4, 5].map((t) => (
            <option key={t} value={t}>
              Tier {t}
            </option>
          ))}
        </select>
      </div>
      {error && <p className="error">{error}</p>}
      <table className="leaderboard">
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
            entries.map((e, i) => (
              <tr key={`${e.accountId}-${i}`}>
                <td>{i + 1}</td>
                <td>{e.displayName}</td>
                <td>{e.elapsedSeconds.toFixed(1)}s</td>
              </tr>
            ))
          )}
        </tbody>
      </table>
    </section>
  );
}
