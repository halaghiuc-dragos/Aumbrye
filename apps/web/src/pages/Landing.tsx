import { Link } from "react-router-dom";
import { PageHelmet } from "../components/Layout";
import PrerenderReady from "../components/PrerenderReady";

export default function LandingPage() {
  return (
    <section className="landing">
      <PageHelmet
        title="Aumbrye — Action Roguelite RPG"
        description="Handcrafted runs, soulslike combat, and five deadly biomes await in Aumbrye."
        path="/"
      />
      <PrerenderReady />
      <div className="hero">
        <p className="eyebrow">Action Roguelite RPG</p>
        <h1>Aumbrye</h1>
        <p className="subtitle">
          Handcrafted runs. Soulslike combat. Five deadly biomes await.
        </p>
        <div className="cta-row">
          <a className="cta primary" href="#mailing-list">
            Join the mailing list
          </a>
          <Link className="cta secondary" to="/account">
            Sign in
          </Link>
        </div>
      </div>
      <div className="screenshot-panel" id="mailing-list">
        <p>Screenshots coming soon</p>
        <p className="muted">
          Wishlist updates will land here once the Steam app page is live.
        </p>
      </div>
    </section>
  );
}
