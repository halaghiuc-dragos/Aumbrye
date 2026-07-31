import wiki from "../content/wiki/pages.json";

export default function WikiPage() {
  return (
    <section className="page">
      <h2>Wiki</h2>
      {wiki.pages.map((page) => (
        <article key={page.slug} className="card">
          <h3>{page.title}</h3>
          <p>{page.body}</p>
        </article>
      ))}
    </section>
  );
}
