const apiUrl = import.meta.env.VITE_API_URL ?? "http://localhost:5000";

export default function App() {
  return (
    <main className="landing">
      <h1>Aumbrye</h1>
      <p className="subtitle">Action roguelite RPG</p>
      {import.meta.env.DEV && (
        <p className="api-hint">API: {apiUrl}</p>
      )}
    </main>
  );
}
