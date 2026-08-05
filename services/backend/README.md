# Aumbrye API

ASP.NET Core backend for accounts, saves, and run validation.

## Local development

```bash
cd services/backend
dotnet restore Aumbrye.sln
dotnet run --project src/Aumbrye.Api
```

## Configuration

`src/Aumbrye.Api/appsettings.json` ships **development-only** defaults:

| Setting | Dev default | Production override |
|---------|-------------|-------------------|
| `Jwt:Secret` | `dev-only-change-me-in-production-32chars!!` | `Jwt__Secret` env var |
| `ConnectionStrings:DefaultConnection` | local Postgres `aumbrye` / `aumbrye_dev` | `ConnectionStrings__DefaultConnection` |
| `ConnectionStrings:Redis` | `localhost:6379` | `ConnectionStrings__Redis` |

Deploys **must** set secrets via environment variables or a secrets manager. Never commit production credentials.

Example Docker / compose override:

```yaml
environment:
  Jwt__Secret: "${AUMBRYE_JWT_SECRET}"
  ConnectionStrings__DefaultConnection: "Host=db;Database=aumbrye;Username=app;Password=${DB_PASSWORD}"
```
