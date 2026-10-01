# Aumbrye API

ASP.NET Core backend (.NET 10) for accounts, saves, run validation and leaderboards. The game client
does not call it: `ApiConfig.ONLINE_ENABLED` is `false` in `apps/game/client/scripts/net/api_config.gd`.

## Layout

| Project | Role |
|---------|------|
| `src/Aumbrye.Api` | HTTP endpoints and middleware |
| `src/Aumbrye.Application` | Services and abstractions |
| `src/Aumbrye.Domain` | Domain types |
| `src/Aumbrye.Infrastructure` | Postgres, Redis, JWT and Steam ticket validation |

Routes live under `/api/v1`: `auth` (register, login, refresh, logout, steam), `runs`, `saves`
(`current`), `account`, `leaderboards`, `telemetry/crash` and `health` (`/health/ready` for readiness).

## Local development

```bash
cd services/backend
dotnet restore Aumbrye.sln
dotnet run --project src/Aumbrye.Api
```

The API refuses to start without a signing key unless it runs against in-memory stores. Start the
datastores with `docker compose up -d` from the repository root, then export:

| Setting | Value |
|---------|-------|
| `Jwt__Secret` | Base64 that decodes to at least 32 bytes (`openssl rand -base64 48`) |
| `ConnectionStrings__DefaultConnection` | Postgres, for example `Host=localhost;Port=5432;Database=aumbrye;Username=aumbrye;Password=aumbrye_dev` |
| `ConnectionStrings__Redis` | `localhost:6379` |
| `Steam__WebApiKey`, `Steam__AppId` | Optional; without the key `/auth/steam` answers 503 |

`appsettings.json` carries only logging, CORS (`http://localhost:5173`) and the JWT issuer, audience
and 15-minute access-token lifetime; no secrets. `appsettings.Development.json.example` shows the
connection strings. `UseInMemoryStores=true` (or the `Testing` environment) swaps Postgres and Redis for
in-memory stores and a fixed signing key, for local experiments only.

Never commit production credentials; set secrets through environment variables or a secrets manager.
