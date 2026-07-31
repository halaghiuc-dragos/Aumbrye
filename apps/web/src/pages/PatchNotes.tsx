import patchNotes from "../content/patch-notes/entries.json";

export default function PatchNotesPage() {
  return (
    <section className="page">
      <h2>Patch Notes</h2>
      {patchNotes.entries.map((entry) => (
        <article key={entry.version} className="card">
          <h3>
            v{entry.version} — {entry.title}
          </h3>
          <p className="muted">{entry.date}</p>
          <ul>
            {entry.highlights.map((h) => (
              <li key={h}>{h}</li>
            ))}
          </ul>
        </article>
      ))}
    </section>
  );
}
