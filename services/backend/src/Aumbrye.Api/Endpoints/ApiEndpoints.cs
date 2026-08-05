using System.Security.Claims;
using System.Text.Json;
using System.Text.Json.Nodes;
using Aumbrye.Application.Abstractions;
using Aumbrye.Application.Services;
using Aumbrye.Shared.Contracts;
using Aumbrye.Shared.Contracts.Auth;
using Aumbrye.Shared.Contracts.Runs;
using Aumbrye.Shared.Contracts.Saves;

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
        var logger = app.Services.GetService<ILoggerFactory>()?.CreateLogger("RunsEndpoints");

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
            catch (Exception ex)
            {
                logger?.LogError(ex, "CreateRun failed for biome {BiomeId}", req.BiomeId);
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
            return Results.Ok(new CompleteRunResponse(
                result.RunId,
                result.Status!,
                result.Progression == null
                    ? null
                    : new CompleteRunProgressionResponse(
                        result.Progression.XpGained,
                        result.Progression.TotalXp,
                        result.Progression.Level,
                        result.Progression.TalentPointsEarned,
                        result.Progression.LootGranted.Select(l => new LootGrantedResponse(
                            l["instanceId"]?.GetValue<string>(),
                            l["itemDefId"]?.GetValue<string>(),
                            l["itemId"]?.GetValue<string>(),
                            l["rarity"]?.GetValue<string>(),
                            l["affixCount"]?.GetValue<int>(),
                            l["quantity"]?.GetValue<int>())).ToList(),
                        result.Progression.EconomyNote)));
        });

        return group;
    }

    private static Guid? GetAccountId(ClaimsPrincipal user)
    {
        var id = user.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(id, out var guid) ? guid : null;
    }
}

public static class SavesEndpoints
{
    public static RouteGroupBuilder MapSavesEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/saves").WithTags("Saves").RequireAuthorization();

        group.MapGet("/current", async (
            ClaimsPrincipal user,
            ISaveService saves,
            CancellationToken ct) =>
        {
            var accountId = GetAccountId(user);
            if (accountId == null)
                return Results.Unauthorized();
            var result = await saves.GetCurrentAsync(accountId.Value, ct);
            if (!result.Success)
                return Results.BadRequest(new { error = result.Error });
            var json = result.State!.ToJsonString();
            return Results.Ok(new SaveResponse(json, result.UpdatedAt!.Value));
        });

        group.MapPut("/current", async (
            PutSaveRequest req,
            ClaimsPrincipal user,
            ISaveService saves,
            CancellationToken ct) =>
        {
            var accountId = GetAccountId(user);
            if (accountId == null)
                return Results.Unauthorized();

            JsonObject? state;
            try
            {
                state = JsonNode.Parse(req.StateJson)?.AsObject();
            }
            catch (JsonException)
            {
                return Results.BadRequest(new { error = "Invalid save JSON." });
            }

            if (state == null)
                return Results.BadRequest(new { error = "Save must be a JSON object." });

            var result = await saves.PutCurrentAsync(accountId.Value, state, req.ClientUpdatedAt, ct);
            if (result.Conflict)
            {
                return Results.Conflict(new
                {
                    error = result.Error,
                    state = result.State!.ToJsonString(),
                    updatedAt = result.UpdatedAt,
                });
            }

            if (!result.Success)
                return Results.BadRequest(new { error = result.Error });

            return Results.Ok(new PutSaveResponse(result.UpdatedAt!.Value));
        });

        return group;
    }

    private static Guid? GetAccountId(ClaimsPrincipal user)
    {
        var id = user.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(id, out var guid) ? guid : null;
    }
}
