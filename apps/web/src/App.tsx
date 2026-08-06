import { BrowserRouter, Route, Routes } from "react-router-dom";
import Layout from "./components/Layout";
import NotFound from "./components/NotFound";
import VersionGate from "./components/VersionGate";
import AccountPage from "./pages/Account";
import LandingPage from "./pages/Landing";
import LeaderboardsPage from "./pages/Leaderboards";
import PatchNoteDetailPage from "./pages/PatchNoteDetail";
import PatchNotesPage from "./pages/PatchNotes";
import WikiIndexPage, { WikiArticlePage } from "./pages/Wiki";

export default function App() {
  return (
    <BrowserRouter>
      <VersionGate />
      <Routes>
        <Route element={<Layout />}>
          <Route index element={<LandingPage />} />
          <Route path="account" element={<AccountPage />} />
          <Route path="patch-notes" element={<PatchNotesPage />} />
          <Route path="patch-notes/:version" element={<PatchNoteDetailPage />} />
          <Route path="wiki" element={<WikiIndexPage />} />
          <Route path="wiki/:slug" element={<WikiArticlePage />} />
          <Route path="leaderboards" element={<LeaderboardsPage />} />
          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
