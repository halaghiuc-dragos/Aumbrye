import { Link, useParams } from "react-router-dom";
import { getWikiPage, wikiPages } from "../content/loader";
import NotFound from "../components/NotFound";
import { PageHelmet } from "../components/Layout";

export default function WikiIndexPage() {
  return (
    <section className="page">
      <PageHelmet
        title="Wiki — Aumbrye"
        description="Gameplay guides and FAQ for Aumbrye."
        path="/wiki"
      />
      <h2>Wiki</h2>
      <ul className="content-list">
        {wikiPages.map((page) => (
          <li key={page.slug}>
            <Link to={`/wiki/${page.slug}`}>{page.title}</Link>
          </li>
        ))}
      </ul>
    </section>
  );
}

export function WikiArticlePage() {
  const { slug = "" } = useParams();
  const page = getWikiPage(slug);

  if (!page) {
    return <NotFound />;
  }

  return (
    <section className="page">
      <PageHelmet
        title={`${page.title} — Aumbrye Wiki`}
        description={page.body.slice(0, 155)}
        path={`/wiki/${page.slug}`}
      />
      <p>
        <Link className="muted" to="/wiki">
          ← Back to wiki
        </Link>
      </p>
      <article className="card">
        <h2>{page.title}</h2>
        <p>{page.body}</p>
      </article>
    </section>
  );
}
