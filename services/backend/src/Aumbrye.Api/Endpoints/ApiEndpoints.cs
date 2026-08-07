using System.Security.Claims;
using System.Text.Json;
using System.Text.Json.Nodes;
using Aumbrye.Application.Abstractions;
using Aumbrye.Application.Services;
using Aumbrye.Shared.Contracts;
using Aumbrye.Shared.Contracts.Auth;
using Aumbrye.Shared.Contracts.Leaderboards;
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
                return ProblemResults.BadRequest(result.Error!);
            return Results.Ok(ToResponse(result));
        })
        .WithName("Register")
        .RequireRateLimiting("auth")
        .Produces<AuthResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status429TooManyRequests);

        group.MapPost("/login", async (LoginRequest req, IAuthService auth, CancellationToken ct) =>
        {
            var result = await auth.LoginAsync(req.Email, req.Password, ct);
            if (!result.Success)
                return ProblemResults.Unauthorized(result.Error!);
            return Results.Ok(ToResponse(result));
        })
        .WithName("Login")
        .RequireRateLimiting("auth")
        .Produces<AuthResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .Produces(StatusCodes.Status429TooManyRequests);

        group.MapPost("/refresh", async (RefreshRequest req, IAuthService auth, CancellationToken ct) =>
        {
            var result = await auth.RefreshAsync(req.RefreshToken, ct);
            if (!result.Success)
                return ProblemResults.Unauthorized(result.Error!);
            return Results.Ok(ToResponse(result));
        })
        .WithName("Refresh")
        .RequireRateLimiting("auth")
        .Produces<AuthResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .Produces(StatusCodes.Status429TooManyRequests);

        group.MapPost("/logout", async (
            LogoutRequest req,
            ClaimsPrincipal user,
            IAuthService auth,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();
            await auth.LogoutAsync(accountId.Value, req.RefreshToken, ct);
            return Results.NoContent();
        })
        .WithName("Logout")
        .RequireAuthorization()
        .RequireRateLimiting("auth")
        .Produces(StatusCodes.Status204NoContent)
        .ProducesProblem(StatusCodes.Status401Unauthorized);

        group.MapPost("/steam", async (SteamAuthRequest req, IAuthService auth, CancellationToken ct) =>
        {
            var result = await auth.AuthenticateSteamAsync(req.TicketHex, req.AppId, ct);
            if (!result.Success)
            {
                return result.ErrorStatus switch
                {
                    503 => ProblemResults.ServiceUnavailable(result.Error!),
                    400 => ProblemResults.BadRequest(result.Error!),
                    _ => ProblemResults.Unauthorized(result.Error!),
                };
            }
            return Results.Ok(ToResponse(result));
        })
        .WithName("SteamAuth")
        .RequireRateLimiting("auth")
        .Produces<AuthResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status503ServiceUnavailable)
        .Produces(StatusCodes.Status429TooManyRequests);

        return group;
    }

    private static AuthResponse ToResponse(AuthResult result) =>
        new(
            new AuthTokensResponse(result.AccessToken!, result.RefreshToken!, result.AccessTokenExpiresAt!.Value),
            new AuthUserResponse(result.AccountId!.Value, result.Email ?? string.Empty));
}

public static class RunsEndpoints
{
    public static RouteGroupBuilder MapRunsEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/runs").WithTags("Runs").RequireAuthorization().RequireRateLimiting("runs");

        group.MapPost("/", async (
            CreateRunRequest req,
            ClaimsPrincipal user,
            IRunService runs,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();
            var result = await runs.CreateRunAsync(accountId.Value, req.BiomeId, req.Seed, req.Tier, ct);
            if (!result.Success)
                return result.IsInternalError
                    ? ProblemResults.InternalError(result.Error!)
                    : ProblemResults.BadRequest(result.Error!);
            return Results.Ok(new CreateRunResponse(
                result.RunId,
                result.Seed,
                result.BiomeId!,
                result.DefinitionJson!));
        })
        .WithName("CreateRun")
        .Produces<CreateRunResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status500InternalServerError);

        group.MapGet("/{id:guid}/dungeon", async (
            Guid id,
            int? floor,
            ClaimsPrincipal user,
            IRunService runs,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();
            var json = await runs.GetDungeonDefinitionAsync(accountId.Value, id, floor ?? 1, ct);
            if (json == null)
                return Results.NotFound();
            return Results.Content(json, "application/json");
        })
        .WithName("GetRunDungeon")
        .Produces<string>(StatusCodes.Status200OK, "application/json")
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .Produces(StatusCodes.Status404NotFound);

        group.MapPost("/{id:guid}/complete", async (
            Guid id,
            CompleteRunRequest req,
            ClaimsPrincipal user,
            IRunService runs,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();
            var result = await runs.CompleteRunAsync(
                accountId.Value,
                id,
                new CompleteRunInput(
                    req.Outcome,
                    req.ElapsedSeconds,
                    req.BossDefeated,
                    req.LootClaimedInstanceIds ?? [],
                    req.Floor),
                ct);
            if (!result.Success)
                return ProblemResults.BadRequest(result.Error!);
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
                        result.Progression.EconomyNote,
                        result.Progression.CharacterStateJson)));
        })
        .WithName("CompleteRun")
        .Produces<CompleteRunResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status401Unauthorized);

        return group;
    }
}

public static class SavesEndpoints
{
    public static RouteGroupBuilder MapSavesEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/saves").WithTags("Saves").RequireAuthorization().RequireRateLimiting("saves");

        group.MapGet("/current", async (
            ClaimsPrincipal user,
            ISaveService saves,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();
            var result = await saves.GetCurrentAsync(accountId.Value, ct);
            if (!result.Success)
                return ProblemResults.BadRequest(result.Error!);
            var json = result.State!.ToJsonString();
            return Results.Ok(new SaveResponse(json, result.UpdatedAt!.Value));
        })
        .WithName("GetCurrentSave")
        .Produces<SaveResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status401Unauthorized);

        group.MapPut("/current", async (
            PutSaveRequest req,
            ClaimsPrincipal user,
            ISaveService saves,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();

            JsonObject? state;
            try
            {
                state = JsonNode.Parse(req.StateJson)?.AsObject();
            }
            catch (JsonException)
            {
                return ProblemResults.BadRequest("Invalid save JSON.");
            }

            if (state == null)
                return ProblemResults.BadRequest("Save must be a JSON object.");

            var result = await saves.PutCurrentAsync(accountId.Value, state, req.ClientUpdatedAt, ct);
            if (result.Conflict)
            {
                return Results.Conflict(new PutSaveResponse(
                    result.UpdatedAt!.Value,
                    Conflict: true,
                    ServerStateJson: result.State!.ToJsonString()));
            }

            if (!result.Success)
                return ProblemResults.BadRequest(result.Error!);

            return Results.Ok(new PutSaveResponse(result.UpdatedAt!.Value));
        })
        .WithName("PutCurrentSave")
        .Produces<PutSaveResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .Produces<PutSaveResponse>(StatusCodes.Status409Conflict);

        return group;
    }
}

public static class AccountEndpoints
{
    public static RouteGroupBuilder MapAccountEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/account").WithTags("Account").RequireAuthorization();

        group.MapPut("/display-name", async (
            UpdateDisplayNameRequest req,
            ClaimsPrincipal user,
            IAccountService accounts,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();
            var result = await accounts.UpdateDisplayNameAsync(accountId.Value, req.DisplayName, ct);
            if (!result.Success)
                return ProblemResults.BadRequest(result.Error!);
            return Results.Ok(new UpdateDisplayNameResponse(result.DisplayName!));
        })
        .WithName("UpdateDisplayName")
        .Produces<UpdateDisplayNameResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status401Unauthorized);

        group.MapDelete("/", async (
            ClaimsPrincipal user,
            IAccountService accounts,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();
            var deleted = await accounts.DeleteAccountAsync(accountId.Value, ct);
            if (!deleted)
                return ProblemResults.NotFound("Account not found.");
            return Results.NoContent();
        })
        .WithName("DeleteAccount")
        .Produces(StatusCodes.Status204NoContent)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        group.MapGet("/export", async (
            ClaimsPrincipal user,
            IAccountService accounts,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();
            var export = await accounts.ExportAccountAsync(accountId.Value, ct);
            if (export == null)
                return ProblemResults.NotFound("Account not found.");
            return Results.Json(export);
        })
        .WithName("ExportAccount")
        .Produces<JsonObject>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status404NotFound);

        group.MapPost("/link-steam", async (
            LinkSteamRequest req,
            ClaimsPrincipal user,
            IAuthService auth,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();
            var result = await auth.LinkSteamAsync(accountId.Value, req.TicketHex, req.AppId, ct);
            if (!result.Success)
            {
                return result.ErrorStatus switch
                {
                    503 => ProblemResults.ServiceUnavailable(result.Error!),
                    400 => ProblemResults.BadRequest(result.Error!),
                    409 => ProblemResults.Conflict(result.Error!),
                    404 => ProblemResults.NotFound(result.Error!),
                    _ => ProblemResults.Unauthorized(result.Error!),
                };
            }
            return Results.NoContent();
        })
        .WithName("LinkSteam")
        .Produces(StatusCodes.Status204NoContent)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status409Conflict)
        .ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        return group;
    }
}
