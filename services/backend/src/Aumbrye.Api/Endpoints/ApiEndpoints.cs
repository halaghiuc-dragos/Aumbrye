using System.Security.Claims;
using Aumbrye.Application.Abstractions;
using Aumbrye.Shared.Contracts;
using Aumbrye.Shared.Contracts.Auth;
using Aumbrye.Shared.Contracts.Runs;

namespace Aumbrye.Api.Auth;

public static class AuthEndpoints
{
    public static RouteGroupBuilder MapAuthEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/auth").WithTags("Auth");

        group.MapPost("/register", async (RegisterRequest req, IAuthService auth, CancellationToken ct) =>
        {
            var result = await auth.RegisterAsync(req.Email, req.Password, ct);
            if (!result.Success)
                return Results.BadRequest(new { error = result.Error });
            return Results.Ok(ToResponse(result));
        }).RequireRateLimiting("auth");

        group.MapPost("/login", async (LoginRequest req, IAuthService auth, CancellationToken ct) =>
        {
            var result = await auth.LoginAsync(req.Email, req.Password, ct);
            if (!result.Success)
                return Results.Json(new { error = result.Error }, statusCode: StatusCodes.Status401Unauthorized);
            return Results.Ok(ToResponse(result));
        }).RequireRateLimiting("auth");

        group.MapPost("/refresh", async (RefreshRequest req, IAuthService auth, CancellationToken ct) =>
        {
            var result = await auth.RefreshAsync(req.RefreshToken, ct);
            if (!result.Success)
                return Results.Json(new { error = result.Error }, statusCode: StatusCodes.Status401Unauthorized);
            return Results.Ok(ToResponse(result));
        }).RequireRateLimiting("auth");

        return group;
    }

    private static AuthResponse ToResponse(AuthResult result) =>
        new(
            new AuthTokensResponse(result.AccessToken!, result.RefreshToken!, result.AccessTokenExpiresAt!.Value),
            new AuthUserResponse(result.AccountId!.Value, result.Email!));
}

public static class RunsEndpoints
{
    public static RouteGroupBuilder MapRunsEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/runs").WithTags("Runs").RequireAuthorization();

        group.MapPost("/", async (
            CreateRunRequest req,
            ClaimsPrincipal user,
            IRunService runs,
            CancellationToken ct) =>
        {
            try
            {
                var accountId = GetAccountId(user);
                if (accountId == null)
                    return Results.Unauthorized();
                var result = await runs.CreateRunAsync(accountId.Value, req.BiomeId, req.Seed, req.Tier, ct);
                if (!result.Success)
                    return Results.BadRequest(new { error = result.Error });
                return Results.Ok(new CreateRunResponse(
                    result.RunId,
                    result.Seed,
                    result.BiomeId!,
                    result.DefinitionJson!));
            }
            catch (Exception)
            {
                return Results.Json(
                    new { error = "Failed to create run." },
                    statusCode: StatusCodes.Status500InternalServerError);
            }
        });

        group.MapGet("/{id:guid}/dungeon", async (
            Guid id,
            ClaimsPrincipal user,
            IRunService runs,
            CancellationToken ct) =>
        {
            var accountId = GetAccountId(user);
            if (accountId == null)
                return Results.Unauthorized();
            var json = await runs.GetDungeonDefinitionAsync(accountId.Value, id, ct);
            if (json == null)
                return Results.NotFound();
            return Results.Content(json, "application/json");
        });

        group.MapPost("/{id:guid}/complete", async (
            Guid id,
            CompleteRunRequest req,
            ClaimsPrincipal user,
            IRunService runs,
            CancellationToken ct) =>
        {
            var accountId = GetAccountId(user);
            if (accountId == null)
                return Results.Unauthorized();
            var result = await runs.CompleteRunAsync(
                accountId.Value,
                id,
                new CompleteRunInput(req.Outcome, req.ElapsedSeconds, req.BossDefeated, req.LootClaimedInstanceIds ?? []),
                ct);
            if (!result.Success)
                return Results.BadRequest(new { error = result.Error });
            return Results.Ok(new CompleteRunResponse(result.RunId, result.Status!));
        });

        return group;
    }

    private static Guid? GetAccountId(ClaimsPrincipal user)
    {
        var id = user.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(id, out var guid) ? guid : null;
    }
}
