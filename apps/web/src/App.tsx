import { useState } from "react";
import LandingPage from "./pages/Landing";
import AccountPage from "./pages/Account";
import PatchNotesPage from "./pages/PatchNotes";
import WikiPage from "./pages/Wiki";
import LeaderboardsPage from "./pages/Leaderboards";

type Page = "home" | "account" | "patch-notes" | "wiki" | "leaderboards";

const NAV: { id: Page; label: string }[] = [
  { id: "home", label: "Home" },
  { id: "account", label: "Account" },
  { id: "patch-notes", label: "Patch Notes" },
  { id: "wiki", label: "Wiki" },
  { id: "leaderboards", label: "Leaderboards" },
];

export default function App() {
  const [page, setPage] = useState<Page>("home");

  return (
    <>
      <header className="site-header">
        <button type="button" className="brand" onClick={() => setPage("home")}>
          Aumbrye
        </button>
        <nav>
          {NAV.map((item) => (
            <button
              key={item.id}
              type="button"
              className={page === item.id ? "active" : ""}
              onClick={() => setPage(item.id)}
            >
              {item.label}
            </button>
          ))}
        </nav>
      </header>
      <main>
        {page === "home" && <LandingPage onNavigate={(p) => setPage(p as Page)} />}
        {page === "account" && <AccountPage />}
        {page === "patch-notes" && <PatchNotesPage />}
        {page === "wiki" && <WikiPage />}
        {page === "leaderboards" && <LeaderboardsPage />}
      </main>
      <footer className="site-footer">
        <p>© Aumbrye — Early Access</p>
      </footer>
    </>
  );
}
