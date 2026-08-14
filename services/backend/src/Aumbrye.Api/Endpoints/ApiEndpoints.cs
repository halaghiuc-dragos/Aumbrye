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

        group.MapPost("/register", async (
            RegisterRequest req,
            HttpContext http,
            IAuthService auth,
            CancellationToken ct) =>
        {
            var result = await auth.RegisterAsync(req.Email, req.Password, ct);
            if (!result.Success)
                return ProblemResults.BadRequest(result.Error!);
            return Results.Ok(ToResponse(result, http));
        })
        .WithName("Register")
        .RequireRateLimiting("register")
        .Produces<AuthResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status429TooManyRequests);

        group.MapPost("/login", async (
            LoginRequest req,
            HttpContext http,
            IAuthService auth,
            CancellationToken ct) =>
        {
            var result = await auth.LoginAsync(req.Email, req.Password, ct);
            if (!result.Success)
                return ProblemResults.Unauthorized(result.Error!);
            return Results.Ok(ToResponse(result, http));
        })
        .WithName("Login")
        .RequireRateLimiting("auth")
        .Produces<AuthResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .Produces(StatusCodes.Status429TooManyRequests);

        group.MapPost("/refresh", async (
            RefreshRequest req,
            HttpContext http,
            IAuthService auth,
            CancellationToken ct) =>
        {
            // Cookie clients send no body token; fall back to the httpOnly cookie.
            var token = string.IsNullOrEmpty(req.RefreshToken)
                ? http.Request.Cookies[AuthTransport.CookieName]
                : req.RefreshToken;
            if (string.IsNullOrEmpty(token))
                return ProblemResults.Unauthorized("Invalid refresh token.");

            var result = await auth.RefreshAsync(token, ct);
            if (!result.Success)
            {
                ClearRefreshCookie(http);
                return ProblemResults.Unauthorized(result.Error!);
            }
            return Results.Ok(ToResponse(result, http));
        })
        .WithName("Refresh")
        .RequireRateLimiting("auth")
        .Produces<AuthResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .Produces(StatusCodes.Status429TooManyRequests);

        group.MapPost("/logout", async (
            LogoutRequest req,
            HttpContext http,
            ClaimsPrincipal user,
            IAuthService auth,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();
            var token = string.IsNullOrEmpty(req.RefreshToken)
                ? http.Request.Cookies[AuthTransport.CookieName]
                : req.RefreshToken;
            if (!string.IsNullOrEmpty(token))
                await auth.LogoutAsync(accountId.Value, token, ct);
            ClearRefreshCookie(http);
            return Results.NoContent();
        })
        .WithName("Logout")
        .RequireAuthorization()
        .RequireRateLimiting("auth")
        .Produces(StatusCodes.Status204NoContent)
        .ProducesProblem(StatusCodes.Status401Unauthorized);

        group.MapPost("/steam", async (
            SteamAuthRequest req,
            HttpContext http,
            IAuthService auth,
            CancellationToken ct) =>
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
            return Results.Ok(ToResponse(result, http));
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

    /// <summary>
    /// Builds the auth payload, honouring the client's chosen refresh-token transport.
    /// </summary>
    /// <remarks>
    /// With cookie transport the refresh token is written to an httpOnly, Secure, SameSite=Strict
    /// cookie and omitted from the JSON body, so an XSS payload cannot read it — the previous
    /// sessionStorage approach handed any injected script a 30-day account takeover.
    /// </remarks>
    private static AuthResponse ToResponse(AuthResult result, HttpContext http)
    {
        var refreshToken = result.RefreshToken;
        if (UsesCookieTransport(http))
        {
            SetRefreshCookie(http, refreshToken!);
            refreshToken = null;
        }

        return new AuthResponse(
            new AuthTokensResponse(result.AccessToken!, refreshToken, result.AccessTokenExpiresAt!.Value),
            new AuthUserResponse(result.AccountId!.Value, result.Email ?? string.Empty));
    }

    private static bool UsesCookieTransport(HttpContext http) =>
        string.Equals(
            http.Request.Headers[AuthTransport.HeaderName].FirstOrDefault(),
            AuthTransport.Cookie,
            StringComparison.OrdinalIgnoreCase);

    private static void SetRefreshCookie(HttpContext http, string refreshToken) =>
        http.Response.Cookies.Append(
            AuthTransport.CookieName,
            refreshToken,
            new CookieOptions
            {
                HttpOnly = true,
                // Allow plain HTTP only for local development, where there is no TLS to ride on.
                Secure = !http.Request.Host.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase),
                SameSite = SameSiteMode.Strict,
                Path = AuthTransport.CookiePath,
                MaxAge = TimeSpan.FromDays(30),
            });

    private static void ClearRefreshCookie(HttpContext http) =>
        http.Response.Cookies.Delete(
            AuthTransport.CookieName, new CookieOptions { Path = AuthTransport.CookiePath });
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
            var result = await runs.GetDungeonDefinitionAsync(accountId.Value, id, floor ?? 1, ct);
            if (result.NotFound)
                return Results.NotFound();
            if (!result.Success)
                return ProblemResults.BadRequest(result.Error!);
            return Results.Content(result.Json!, "application/json");
        })
        .WithName("GetRunDungeon")
        .Produces<string>(StatusCodes.Status200OK, "application/json")
        .ProducesProblem(StatusCodes.Status400BadRequest)
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
                    req.Floor,
                    req.Kills),
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
            {
                return result.ErrorStatus == StatusCodes.Status422UnprocessableEntity
                    ? ProblemResults.UnprocessableEntity(result.Error!)
                    : ProblemResults.BadRequest(result.Error!);
            }
            var json = result.State!.ToJsonString();
            return Results.Ok(new SaveResponse(json, result.UpdatedAt!.Value));
        })
        .WithName("GetCurrentSave")
        .Produces<SaveResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPut("/current", async (
            PutSaveRequest req,
            ClaimsPrincipal user,
            ISaveService saves,
            CancellationToken ct) =>
        {
            var accountId = user.AccountId();
            if (accountId == null)
                return Results.Unauthorized();

            // Reject oversized bodies before parsing them — a 100 MB blob is both a storage and a
            // JSON-parse denial-of-service, and no legitimate save comes close to the cap.
            if (SaveService.ByteLength(req.StateJson) > SaveStateValidator.MaxStateJsonBytes)
            {
                return ProblemResults.PayloadTooLarge(
                    $"Save exceeds the {SaveStateValidator.MaxStateJsonBytes / 1024} KB limit.");
            }

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
        .Produces<PutSaveResponse>(StatusCodes.Status409Conflict)
        .ProducesProblem(StatusCodes.Status413PayloadTooLarge);

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
