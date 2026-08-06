import { Helmet } from "react-helmet-async";
import { Link } from "react-router-dom";

export default function NotFound() {
  return (
    <section className="page">
      <Helmet>
        <title>Page not found — Aumbrye</title>
        <meta name="description" content="The requested Aumbrye page could not be found." />
        <link rel="canonical" href={`${window.location.origin}/404`} />
      </Helmet>
      <h2>Page not found</h2>
      <p className="muted">That route does not exist.</p>
      <Link className="cta secondary" to="/">
        Back to home
      </Link>
    </section>
  );
}
