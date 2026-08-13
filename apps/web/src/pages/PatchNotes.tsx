import { Link } from "react-router-dom";
import { patchNotes } from "../content/loader";
import { PageHelmet } from "../components/Layout";
import PrerenderReady from "../components/PrerenderReady";

export default function PatchNotesPage() {
  return (
    <section className="page">
      <PageHelmet
        title="Patch Notes — Aumbrye"
        description="Release notes for Aumbrye game updates."
        path="/patch-notes"
      />
      <PrerenderReady />
      <h2>Patch Notes</h2>
      {patchNotes.map((entry) => (
        <article key={entry.slug} className="card">
          <h3>
            <Link to={`/patch-notes/${entry.slug}`}>
              v{entry.version} — {entry.title}
            </Link>
          </h3>
          <p className="muted">{entry.date}</p>
          <ul>
            {entry.highlights.map((highlight) => (
              <li key={highlight}>{highlight}</li>
            ))}
          </ul>
        </article>
      ))}
    </section>
  );
}
