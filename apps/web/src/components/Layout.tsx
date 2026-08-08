import { Helmet } from "react-helmet-async";
import { NavLink, Outlet } from "react-router-dom";

const NAV: { to: string; label: string; end?: boolean }[] = [
  { to: "/", label: "Home", end: true },
  { to: "/account", label: "Account" },
  { to: "/patch-notes", label: "Patch Notes" },
  { to: "/wiki", label: "Wiki" },
  { to: "/leaderboards", label: "Leaderboards" },
];

export default function Layout() {
  return (
    <>
      <a className="skip-link" href="#main-content">
        Skip to main content
      </a>
      <header className="site-header">
        <NavLink to="/" className="brand" end>
          Aumbrye
        </NavLink>
        <nav aria-label="Primary">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) => (isActive ? "active" : undefined)}
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
      </header>
      <main id="main-content">
        <Outlet />
      </main>
      <footer className="site-footer">
        <p>
          © Aumbrye — Early Access · Site v{__APP_VERSION__} (game patch notes list game versions
          separately)
        </p>
      </footer>
    </>
  );
}

export function PageHelmet({
  title,
  description,
  path,
}: {
  title: string;
  description: string;
  path: string;
}) {
  const canonical = `${window.location.origin}${path}`;
  return (
    <Helmet>
      <title>{title}</title>
      <meta name="description" content={description} />
      <link rel="canonical" href={canonical} />
      <meta property="og:title" content={title} />
      <meta property="og:description" content={description} />
      <meta property="og:url" content={canonical} />
      <meta property="og:type" content="website" />
    </Helmet>
  );
}
