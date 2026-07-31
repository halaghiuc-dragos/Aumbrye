using Aumbrye.Application.Services;

namespace Aumbrye.Api.Auth;

public static class LeaderboardsEndpoints
{
    public static RouteGroupBuilder MapLeaderboardsEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/leaderboards").WithTags("Leaderboards");

        group.MapGet("/", async (
            string? biomeId,
            int? tier,
            int? limit,
            ILeaderboardService leaderboards,
            CancellationToken ct) =>
        {
            var biome = biomeId ?? "forgotten_castle";
            var tierValue = tier ?? 1;
            var top = await leaderboards.GetTopAsync(biome, tierValue, limit ?? 10, ct);
            return Results.Ok(new
            {
                biomeId = biome,
                tier = tierValue,
                entries = top.Select(e => new
                {
                    accountId = e.AccountId,
                    displayName = e.DisplayName,
                    elapsedSeconds = e.ElapsedSeconds,
                    submittedAt = e.SubmittedAt,
                }),
            });
        });

        group.MapPost("/submit", async (
            SubmitLeaderboardRequest req,
            HttpContext http,
            ILeaderboardService leaderboards,
            CancellationToken ct) =>
        {
            var accountIdClaim = http.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
            if (!Guid.TryParse(accountIdClaim, out var accountId))
                return Results.Unauthorized();
            if (!req.OptIn)
                return Results.Ok(new { submitted = false, reason = "opt_out" });
            await leaderboards.SubmitScoreAsync(accountId, req.BiomeId, req.Tier, req.ElapsedSeconds, ct);
            return Results.Ok(new { submitted = true });
        }).RequireAuthorization();

        return group;
    }
}

public sealed record SubmitLeaderboardRequest(
    string BiomeId,
    int Tier,
    double ElapsedSeconds,
    bool OptIn);
