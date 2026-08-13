# Roadmap — password reset and OAuth

Status: **planned**. Password auth has no verification or reset flow, and OAuth is deferred
(the Account page says so in as many words).

## Why this is urgent before broad Early Access

A forgotten password is currently unrecoverable account loss. For a game with cloud saves that is
not a minor gap — it is a support incident per occurrence, and the player has no self-service path
back to their character. Password reset should land *before* a wide release; OAuth can follow.

## Phase 1 — password reset

### Data

`PasswordResetToken`: `AccountId`, `TokenHash` (SHA-256 of the emailed token — never the token
itself), `ExpiresAt` (30 minutes), `UsedAt`, `CreatedAt`. Index on `TokenHash` and `ExpiresAt`; the
existing hourly cleanup service should sweep it with the same set-based delete used for refresh
tokens.

### Endpoints

- `POST /auth/forgot { email }` — **always** returns 204, whether or not the address exists.
  Rate-limited to 3/hour/IP on its own policy. Emails a one-time link.
- `POST /auth/reset { token, newPassword }` — verifies the hash and expiry, rehashes with
  BCrypt at work factor 11, marks the token used, and **revokes every refresh-token family for the
  account**. A reset must log out every existing session; that is the whole point of resetting after
  a compromise.

### Mail

Introduce `IEmailSender` with a console implementation for development and a real transport behind
configuration. No production deployment ships with the console sender enabled.

### Interaction with existing posture

Registration currently answers "email already registered", which is a deliberate product tradeoff
(a game, not a bank) and is now rate-limited separately. If email verification lands, revisit that
decision at the same time and record the outcome in an ADR — the two should not drift apart.

## Phase 2 — OAuth (Google / Discord)

- `GET /auth/oauth/{provider}` starts the authorization-code flow **server-side**. The client never
  handles provider tokens.
- On first sign-in, link by verified email when one matches an existing account; otherwise create an
  account with `Email = null`, exactly as the Steam path already does.
- Reuse `IssueTokensAsync` unchanged — OAuth is an identity source, not a second session system.
- Browser clients continue to use cookie transport for the refresh token.
- The Godot client stays on Steam auth; there is no reason to embed a browser flow there.

### Web UI

Add "Forgot password" beside the sign-in submit, and provider buttons above the email form with a
clear separator. Replace the "deferred to post-EA" notice only when the buttons actually work.

## Ordering

Phase 1 is a prerequisite for taking real player accounts at scale. Phase 2 is a conversion and
convenience feature and can follow at any point, because it does not change the token pipeline.
