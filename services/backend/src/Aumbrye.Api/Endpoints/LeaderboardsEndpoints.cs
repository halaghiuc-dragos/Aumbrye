using Aumbrye.Application.Services;
using Aumbrye.Shared.Contracts.Leaderboards;

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
            var requestedLimit = limit ?? 10;
            if (requestedLimit is < 1 or > 100)
                return ProblemResults.BadRequest("limit must be between 1 and 100.");

            var top = await leaderboards.GetTopAsync(biome, tierValue, requestedLimit, ct);
            return Results.Ok(new LeaderboardPageResponse(
                biome,
                tierValue,
                top.Select(e => new LeaderboardEntryResponse(
                    e.AccountId,
                    e.DisplayName,
                    e.ElapsedSeconds,
                    e.SubmittedAt)).ToList()));
        })
        .WithName("GetLeaderboard")
        .RequireRateLimiting("public")
        .Produces<LeaderboardPageResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest);

        group.MapPost("/submit", async (
            SubmitLeaderboardRequest req,
            HttpContext http,
            ILeaderboardService leaderboards,
            CancellationToken ct) =>
        {
            var accountId = http.User.AccountId();
            if (accountId == null)
                return Results.Unauthorized();

            var result = await leaderboards.SubmitFromRunAsync(accountId.Value, req.RunId, req.OptIn, ct);
            if (result.StatusCode == 404)
                return ProblemResults.NotFound(result.Error!);
            if (result.StatusCode == 403)
                return ProblemResults.Forbidden(result.Error!);
            if (result.StatusCode == 400)
                return ProblemResults.BadRequest(result.Error!);
            if (!result.Submitted)
                return Results.Ok(new SubmitLeaderboardResponse(false, Reason: result.Reason));
            return Results.Ok(new SubmitLeaderboardResponse(true, Rank: result.Rank));
        })
        .WithName("SubmitLeaderboard")
        .RequireAuthorization()
        .Produces<SubmitLeaderboardResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status403Forbidden)
        .ProducesProblem(StatusCodes.Status404NotFound);

        return group;
    }
}
