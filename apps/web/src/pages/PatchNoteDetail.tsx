import { Link, useParams } from "react-router-dom";
import { getPatchNote } from "../content/loader";
import NotFound from "../components/NotFound";
import { PageHelmet } from "../components/Layout";

export default function PatchNoteDetailPage() {
  const { version = "" } = useParams();
  const entry = getPatchNote(version);

  if (!entry) {
    return <NotFound />;
  }

  return (
    <section className="page">
      <PageHelmet
        title={`v${entry.version} — ${entry.title}`}
        description={entry.highlights.join(" ")}
        path={`/patch-notes/${entry.slug}`}
      />
      <p>
        <Link className="muted" to="/patch-notes">
          ← Back to patch notes
        </Link>
      </p>
      <article className="card">
        <h2>
          v{entry.version} — {entry.title}
        </h2>
        <p className="muted">{entry.date}</p>
        <ul>
          {entry.highlights.map((highlight) => (
            <li key={highlight}>{highlight}</li>
          ))}
        </ul>
        {entry.body && <p>{entry.body}</p>}
      </article>
    </section>
  );
}
