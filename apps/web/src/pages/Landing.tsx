type Props = { onNavigate: (page: string) => void };

export default function LandingPage({ onNavigate }: Props) {
  return (
    <section className="landing">
      <div className="hero">
        <p className="eyebrow">Action Roguelite RPG</p>
        <h1>Aumbrye</h1>
        <p className="subtitle">
          Handcrafted runs. Soulslike combat. Five deadly biomes await.
        </p>
        <div className="cta-row">
          <a className="cta primary" href="https://store.steampowered.com/" target="_blank" rel="noreferrer">
            Wishlist on Steam
          </a>
          <button type="button" className="cta secondary" onClick={() => onNavigate("account")}>
            Sign in
          </button>
        </div>
      </div>
      <div className="screenshot-row">
        <div className="screenshot placeholder">Trailer / screenshot slot</div>
        <div className="screenshot placeholder">Biome showcase</div>
        <div className="screenshot placeholder">Combat highlight</div>
      </div>
    </section>
  );
}
