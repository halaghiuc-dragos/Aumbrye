# Post-EA Roadmap (not blocking)

Implement only after EA DoD and retention/combat satisfaction look healthy.

## Content

- Themes 6–20 from original blueprint
- More bosses and enemy variants
- Axe/staff full movesets
- Curse status + deeper ailment builds
- Unique mythic legendaries set

## Meta / live

- Seasonal events
- Hardcore mode
- Daily runs / community challenges
- Expanded leaderboards/seasons

## Platform / social

- Official Steam Deck certification
- Steam Workshop
- Cooperative multiplayer prototype
- Browser supported tier

### OAuth / social login (post-EA only)

Email/password auth ships for EA. OAuth providers (Google, Discord, Steam OpenID) are **deferred
post-EA** — see `services/backend/README.md` for the planned provider table and env keys
(`OAUTH_*`). No client OAuth SDK until retention targets are met; do not block EA on provider keys.

## Tech

- Steam-only auth default
- Deeper anti-cheat / combat validation
- Advanced adaptive audio stems
