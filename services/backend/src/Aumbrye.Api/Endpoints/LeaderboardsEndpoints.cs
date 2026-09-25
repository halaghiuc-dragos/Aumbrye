using Aumbrye.Application.Services;
using Aumbrye.Api.Leaderboards;
using Aumbrye.Shared.Contracts.Leaderboards;
using Aumbrye.Shared.Contracts;

namespace Aumbrye.Api.Auth;

public static class LeaderboardsEndpoints
{
    public static RouteGroupBuilder MapLeaderboardsEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/leaderboards").WithTags("Leaderboards");

        group.MapGet("/", async (
            string? biomeId,
            int? tier,
            int? seed,
            int? playerLevel,
            string? ruleset,
            string? contentVersion,
            int? limit,
            ILeaderboardService leaderboards,
            CancellationToken ct) =>
        {
            var biome = biomeId ?? LeaderboardRules.Biomes[0].Id;
            var tierValue = tier ?? LeaderboardRules.MinimumTier;
            var seedValue = seed ?? 0;
			var playerLevelValue = playerLevel ?? 0;
			var rulesetValue = ruleset ?? RankedLeaderboardContract.Ruleset;
			var contentVersionValue = contentVersion ?? RankedLeaderboardContract.ContentVersion;
            var requestedLimit = limit ?? 10;
            if (requestedLimit is < 1 or > 100)
                return ProblemResults.BadRequest("limit must be between 1 and 100.");
            if (tierValue < LeaderboardRules.MinimumTier || tierValue > LeaderboardRules.MaximumTier)
                return ProblemResults.BadRequest("tier is unavailable.");
            if (!LeaderboardRules.Biomes.Any(option => option.Id == biome))
                return ProblemResults.BadRequest("biome is unavailable.");
			if (seedValue < 1)
				return ProblemResults.BadRequest("seed is required for a comparable ranked board.");
			if (playerLevelValue < 1 || playerLevelValue > 1000)
				return ProblemResults.BadRequest("playerLevel must be between 1 and 1000 for a comparable ranked board.");
			if (!string.Equals(rulesetValue, RankedLeaderboardContract.Ruleset, StringComparison.Ordinal))
				return ProblemResults.BadRequest("ruleset is unavailable.");
			if (!string.Equals(contentVersionValue, RankedLeaderboardContract.ContentVersion, StringComparison.Ordinal))
				return ProblemResults.BadRequest("contentVersion is unavailable.");

            var top = await leaderboards.GetTopAsync(biome, tierValue, seedValue, playerLevelValue, rulesetValue, contentVersionValue, requestedLimit, ct);
            return Results.Ok(new LeaderboardPageResponse(
                biome,
                tierValue,
                seedValue,
                playerLevelValue,
				ApiVersions.ExpectedClientVersion,
				rulesetValue,
				contentVersionValue,
                top.Select(e => new LeaderboardEntryResponse(
                    e.AccountId,
                    e.DisplayName,
                    e.ElapsedSeconds,
                    e.SubmittedAt)).ToList(),
                LeaderboardRules.Capabilities));
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
