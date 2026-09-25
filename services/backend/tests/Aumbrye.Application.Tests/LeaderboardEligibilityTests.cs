using Aumbrye.Application.Services;
using Aumbrye.Application.Abstractions;
using Aumbrye.Domain.Entities;
using Aumbrye.Api.Auth;
using Aumbrye.Api.Middleware;
using Aumbrye.Infrastructure.Persistence;
using Aumbrye.Shared.Contracts.Leaderboards;
using Aumbrye.Shared.Contracts.Runs;
using Aumbrye.Shared.Contracts;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Routing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using System.Security.Claims;
using System.Text.Json;

namespace Aumbrye.Application.Tests;

public static class LeaderboardEligibilityTests
{
    private sealed class RequestBodyDetectionFeature : IHttpRequestBodyDetectionFeature
    {
        public bool CanHaveBody => true;
    }

    private sealed class EmptyDungeonGenerator : IDungeonGenerator
    {
        public (string Json, string? Checksum) Generate(
            string biomeId, int seed, int tier, int playerLevel, Guid runId, int floorIndex = 1, bool isFinalFloor = false) =>
            ("{}", null);
    }

    private sealed class EmptyDungeonCache : IDungeonCache
    {
        public Task SetAsync(Guid runId, int floor, string definitionJson, TimeSpan ttl, CancellationToken ct = default) => Task.CompletedTask;
        public Task<string?> GetAsync(Guid runId, int floor, CancellationToken ct = default) => Task.FromResult<string?>(null);
    }

    public static async Task<int> Main()
    {
        await using var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();
        var options = new DbContextOptionsBuilder<AumbryeDbContext>()
            .UseSqlite(connection)
            .Options;
        await using var db = new AumbryeDbContext(options);
        if (!db.Database.GetMigrations().Contains("20260923100000_RunProgressionVerification")
            || !db.Database.GetMigrations().Contains("20260923130000_RunClientVersionSnapshot"))
        {
            Console.Error.WriteLine("FAIL: run progression verification migration is not discoverable");
            return 1;
        }
        await db.Database.EnsureCreatedAsync();

        var accountId = Guid.NewGuid();
        var runId = Guid.NewGuid();
        var activeRunId = Guid.NewGuid();
        var eligibleRunId = Guid.NewGuid();
        var staleBuildRunId = Guid.NewGuid();
        db.Accounts.Add(new Account
        {
            Id = accountId,
            DisplayName = "RankedTest",
            CreatedAt = DateTimeOffset.UtcNow,
        });
        db.Runs.Add(new Run
        {
            Id = runId,
            AccountId = accountId,
            BiomeId = "forgotten_castle",
            Seed = 12345,
            Tier = 1,
            PlayerLevelSnapshot = 1,
            ClientVersionSnapshot = ApiVersions.ExpectedClientVersion,
            Status = RunStatus.Completed,
            Outcome = "escaped",
            Mode = "dungeon",
            Ruleset = "standard-v1",
            FinalObjectiveCompleted = true,
            RankedDefinitionEligible = true,
            RankedProgressionVerified = false,
            CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-2),
            CompletedAt = DateTimeOffset.UtcNow,
            ElapsedSeconds = 60,
        });
        db.Runs.Add(new Run
        {
            Id = activeRunId,
            AccountId = accountId,
            BiomeId = "forgotten_castle",
            Seed = 54321,
            Tier = 1,
            PlayerLevelSnapshot = 1,
            Status = RunStatus.Active,
            Mode = "dungeon",
            Ruleset = "standard-v1",
            CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-2),
        });
        db.Runs.Add(new Run
        {
            Id = eligibleRunId,
            AccountId = accountId,
            BiomeId = "forgotten_castle",
            Seed = 77777,
            Tier = 1,
            PlayerLevelSnapshot = 1,
            ClientVersionSnapshot = ApiVersions.ExpectedClientVersion,
            Status = RunStatus.Completed,
            Outcome = "escaped",
            Mode = "dungeon",
            Ruleset = "standard-v1",
            FinalObjectiveCompleted = true,
            RankedDefinitionEligible = true,
            RankedProgressionVerified = true,
            CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-2),
            CompletedAt = DateTimeOffset.UtcNow,
            ElapsedSeconds = 60,
        });
        db.Runs.Add(new Run
        {
            Id = staleBuildRunId,
            AccountId = accountId,
            BiomeId = "forgotten_castle",
            Seed = 88888,
            Tier = 1,
            PlayerLevelSnapshot = 1,
            ClientVersionSnapshot = "0.5.0",
            Status = RunStatus.Completed,
            Outcome = "escaped",
            Mode = "dungeon",
            Ruleset = "standard-v1",
            FinalObjectiveCompleted = true,
            RankedDefinitionEligible = true,
            RankedProgressionVerified = true,
            CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-2),
            CompletedAt = DateTimeOffset.UtcNow,
            ElapsedSeconds = 60,
        });
        await db.SaveChangesAsync();

        var store = new InMemoryLeaderboardStore();
        var service = new LeaderboardService(db, store);
        var result = await service.SubmitFromRunAsync(accountId, runId, optIn: true);

        var entries = await store.GetEntriesForAccountAsync(accountId);
        if (result.Submitted
            || result.StatusCode != 400
            || result.Error != "Run is not eligible for this leaderboard."
            || entries.Count != 0)
        {
            Console.Error.WriteLine("FAIL: client-claimed boss/objective state made a run ranked");
            return 1;
        }
        var staleBuildSubmission = await service.SubmitFromRunAsync(accountId, staleBuildRunId, optIn: true);
        if (staleBuildSubmission.Submitted
            || staleBuildSubmission.StatusCode != 400
            || staleBuildSubmission.Error != "Run is not eligible for this leaderboard.")
        {
            Console.Error.WriteLine("FAIL: a run from an unsupported client build entered the current ranked board");
            return 1;
        }

        var runService = new RunService(
            db,
            new EmptyDungeonGenerator(),
            new EmptyDungeonCache(),
            NullLogger<RunService>.Instance);
        var forgedMode = await runService.CompleteRunAsync(
            accountId,
            activeRunId,
            new CompleteRunInput("died", 30, false, [], Mode: "arena"));
        var forgedRuleset = await runService.CompleteRunAsync(
            accountId,
            activeRunId,
            new CompleteRunInput("died", 30, false, [], Ruleset: "modified-v1"));
        if (forgedMode.Success
            || forgedMode.Error != "Run mode cannot be changed at completion."
            || forgedRuleset.Success
            || forgedRuleset.Error != "Run ruleset cannot be changed at completion.")
        {
            Console.Error.WriteLine("FAIL: completion accepted a forged mode or ruleset");
            return 1;
        }

        var createdRun = await runService.CreateRunAsync(accountId, "forgotten_castle", 24680, 1);
        if (!createdRun.Success
            || createdRun.PlayerLevel != 1
            || createdRun.ClientVersion != ApiVersions.ExpectedClientVersion)
        {
            Console.Error.WriteLine("FAIL: server run creation did not return its player-level snapshot");
            return 1;
        }

        var secondAccountId = Guid.NewGuid();
        var submittedAt = DateTimeOffset.UtcNow;
        await store.SubmitScoreAsync(
            accountId, "RankedTest", "forgotten_castle", 1, 12345, 1,
            "standard-v1", RankedLeaderboardContract.ContentVersion, 45, submittedAt);
        await store.SubmitScoreAsync(
            secondAccountId, "RankedTest2", "forgotten_castle", 1, 12345, 2,
            "standard-v1", RankedLeaderboardContract.ContentVersion, 30, submittedAt);
        var levelOneBoard = await store.GetTopAsync(
            "forgotten_castle", 1, 12345, 1, "standard-v1", RankedLeaderboardContract.ContentVersion, 10);
        var levelTwoBoard = await store.GetTopAsync(
            "forgotten_castle", 1, 12345, 2, "standard-v1", RankedLeaderboardContract.ContentVersion, 10);
        if (levelOneBoard.Count != 1
            || levelTwoBoard.Count != 1
            || levelOneBoard[0].PlayerLevel != 1
            || levelTwoBoard[0].PlayerLevel != 2
            || levelOneBoard[0].AccountId == levelTwoBoard[0].AccountId)
        {
            Console.Error.WriteLine("FAIL: leaderboard entries crossed player-level partitions");
            return 1;
        }

        var webBuilder = WebApplication.CreateBuilder();
        webBuilder.Services.AddProblemDetails();
        webBuilder.Services.AddSingleton<ILeaderboardService>(service);
        webBuilder.Services.AddSingleton<IRunService>(runService);
        await using var webApp = webBuilder.Build();
        webApp.MapLeaderboardsEndpoints();
        webApp.MapRunsEndpoints();
        var leaderboardEndpoint = ((IEndpointRouteBuilder)webApp).DataSources
            .SelectMany(source => source.Endpoints)
            .OfType<RouteEndpoint>()
            .Single(endpoint => endpoint.Metadata.GetMetadata<IEndpointNameMetadata>()?.EndpointName == "GetLeaderboard");
        var leaderboardSubmitEndpoint = ((IEndpointRouteBuilder)webApp).DataSources
            .SelectMany(source => source.Endpoints)
            .OfType<RouteEndpoint>()
            .Single(endpoint => endpoint.Metadata.GetMetadata<IEndpointNameMetadata>()?.EndpointName == "SubmitLeaderboard");
        var runCompleteEndpoint = ((IEndpointRouteBuilder)webApp).DataSources
            .SelectMany(source => source.Endpoints)
            .OfType<RouteEndpoint>()
            .Single(endpoint => endpoint.Metadata.GetMetadata<IEndpointNameMetadata>()?.EndpointName == "CompleteRun");

        async Task<(int Status, string Body)> InvokeEndpoint(
            RouteEndpoint endpoint,
            string query = "",
            object? body = null,
            Guid? callerId = null,
            Guid? routeId = null)
        {
            var context = new DefaultHttpContext();
            context.SetEndpoint(endpoint);
            var routePattern = endpoint.RoutePattern.RawText ?? "";
            context.Request.Method = endpoint.Metadata.GetMetadata<HttpMethodMetadata>()?.HttpMethods.FirstOrDefault()
                ?? HttpMethods.Get;
            context.Request.Path = routePattern.Contains("/runs/", StringComparison.Ordinal)
                ? $"/api/v1/runs/{routeId}/complete"
                : routePattern.EndsWith("/submit", StringComparison.Ordinal)
                    ? "/api/v1/leaderboards/submit"
                    : "/api/v1/leaderboards/";
            context.Request.QueryString = new QueryString(query);
            context.Request.RouteValues = new RouteValueDictionary();
            if (routeId.HasValue)
                context.Request.RouteValues["id"] = routeId.Value.ToString();
            context.RequestServices = webApp.Services;
            if (callerId.HasValue)
            {
                context.User = new ClaimsPrincipal(new ClaimsIdentity(
                    [new Claim(ClaimTypes.NameIdentifier, callerId.Value.ToString())], "test"));
            }
            if (body != null)
            {
                var requestBytes = JsonSerializer.SerializeToUtf8Bytes(body, new JsonSerializerOptions(JsonSerializerDefaults.Web));
                context.Request.Body = new MemoryStream(requestBytes);
                context.Request.ContentType = "application/json";
                context.Request.ContentLength = requestBytes.Length;
                context.Features.Set<IHttpRequestBodyDetectionFeature>(new RequestBodyDetectionFeature());
            }
            await using var responseBody = new MemoryStream();
            context.Response.Body = responseBody;
            var endpointHandler = endpoint.RequestDelegate
                ?? throw new InvalidOperationException("HTTP endpoint has no request delegate.");
            await endpointHandler(context);
            responseBody.Position = 0;
            using var reader = new StreamReader(responseBody);
            return (context.Response.StatusCode, await reader.ReadToEndAsync());
        }

        var missingLevelResponse = await InvokeEndpoint(leaderboardEndpoint, "?seed=12345");
        var invalidLevelResponse = await InvokeEndpoint(leaderboardEndpoint, "?seed=12345&playerLevel=0");
        var forgedRulesResponse = await InvokeEndpoint(leaderboardEndpoint, "?seed=12345&playerLevel=1&ruleset=modified-v1");
        var forgedContentVersionResponse = await InvokeEndpoint(leaderboardEndpoint, "?seed=12345&playerLevel=1&contentVersion=old-content");
        var rankedBoardResponse = await InvokeEndpoint(leaderboardEndpoint, "?seed=12345&playerLevel=1");
        var forgedHttpModeResponse = await InvokeEndpoint(
            runCompleteEndpoint,
            body: new CompleteRunRequest("died", 30, false, [], Mode: "arena"),
            callerId: accountId,
            routeId: activeRunId);
        var forgedHttpRulesResponse = await InvokeEndpoint(
            runCompleteEndpoint,
            body: new CompleteRunRequest("died", 30, false, [], Ruleset: "modified-v1"),
            callerId: accountId,
            routeId: activeRunId);
        var forgedHttpMilestoneResponse = await InvokeEndpoint(
            leaderboardSubmitEndpoint,
            body: new SubmitLeaderboardRequest(runId, true),
            callerId: accountId);
        var staleBuildHttpSubmissionResponse = await InvokeEndpoint(
            leaderboardSubmitEndpoint,
            body: new SubmitLeaderboardRequest(staleBuildRunId, true),
            callerId: accountId);
        var eligibleHttpSubmissionResponse = await InvokeEndpoint(
            leaderboardSubmitEndpoint,
            body: new SubmitLeaderboardRequest(eligibleRunId, true),
            callerId: accountId);
        var nextInvokedForOldBuild = false;
        var oldBuildContext = new DefaultHttpContext();
        oldBuildContext.Request.Path = "/api/v1/runs";
        oldBuildContext.Request.Headers[ApiVersions.ClientVersionHeader] = "0.5.0";
        var versionMiddleware = new VersionHeaderMiddleware(
            _ =>
            {
                nextInvokedForOldBuild = true;
                return Task.CompletedTask;
            },
            webApp.Services.GetRequiredService<IProblemDetailsService>());
        await versionMiddleware.InvokeAsync(oldBuildContext);
        var nextInvokedForOldContent = false;
        var oldContentContext = new DefaultHttpContext();
        oldContentContext.Request.Path = "/api/v1/runs";
        oldContentContext.Request.Headers[ApiVersions.ClientVersionHeader] = ApiVersions.ExpectedClientVersion;
        oldContentContext.Request.Headers[ApiVersions.ContentVersionHeader] = "old-content";
        var oldContentMiddleware = new VersionHeaderMiddleware(
            _ =>
            {
                nextInvokedForOldContent = true;
                return Task.CompletedTask;
            },
            webApp.Services.GetRequiredService<IProblemDetailsService>());
        await oldContentMiddleware.InvokeAsync(oldContentContext);
        var nextInvokedForCompatibleBuild = false;
        var compatibleBuildContext = new DefaultHttpContext();
        compatibleBuildContext.Request.Path = "/api/v1/runs";
        compatibleBuildContext.Request.Headers[ApiVersions.ClientVersionHeader] = ApiVersions.ExpectedClientVersion;
        compatibleBuildContext.Request.Headers[ApiVersions.ContentVersionHeader] = ApiVersions.ExpectedContentVersion;
        var compatibleVersionMiddleware = new VersionHeaderMiddleware(
            _ =>
            {
                nextInvokedForCompatibleBuild = true;
                return Task.CompletedTask;
            },
            webApp.Services.GetRequiredService<IProblemDetailsService>());
        await compatibleVersionMiddleware.InvokeAsync(compatibleBuildContext);
        if (missingLevelResponse.Status != StatusCodes.Status400BadRequest
            || invalidLevelResponse.Status != StatusCodes.Status400BadRequest
            || forgedRulesResponse.Status != StatusCodes.Status400BadRequest
            || forgedContentVersionResponse.Status != StatusCodes.Status400BadRequest
            || forgedHttpModeResponse.Status != StatusCodes.Status400BadRequest
            || !forgedHttpModeResponse.Body.Contains("Run mode cannot be changed", StringComparison.Ordinal)
            || forgedHttpRulesResponse.Status != StatusCodes.Status400BadRequest
            || !forgedHttpRulesResponse.Body.Contains("Run ruleset cannot be changed", StringComparison.Ordinal)
            || forgedHttpMilestoneResponse.Status != StatusCodes.Status400BadRequest
            || !forgedHttpMilestoneResponse.Body.Contains("Run is not eligible", StringComparison.Ordinal)
            || staleBuildHttpSubmissionResponse.Status != StatusCodes.Status400BadRequest
            || !staleBuildHttpSubmissionResponse.Body.Contains("Run is not eligible", StringComparison.Ordinal)
            || eligibleHttpSubmissionResponse.Status != StatusCodes.Status200OK
            || !eligibleHttpSubmissionResponse.Body.Contains("\"submitted\":true", StringComparison.Ordinal)
            || oldBuildContext.Response.StatusCode != StatusCodes.Status426UpgradeRequired
            || nextInvokedForOldBuild
            || oldContentContext.Response.StatusCode != StatusCodes.Status400BadRequest
            || nextInvokedForOldContent
            || !nextInvokedForCompatibleBuild
            || rankedBoardResponse.Status != StatusCodes.Status200OK
            || JsonDocument.Parse(rankedBoardResponse.Body).RootElement.GetProperty("playerLevel").GetInt32() != 1
            || JsonDocument.Parse(rankedBoardResponse.Body).RootElement.GetProperty("clientVersion").GetString() != ApiVersions.ExpectedClientVersion)
        {
            Console.Error.WriteLine(
                "FAIL: leaderboard HTTP contracts; missing={0}, invalidLevel={1}, queryRules={2}, mode={3}:{4}, completionRules={5}:{6}, milestone={7}:{8}, valid={9}:{10}",
                missingLevelResponse.Status,
                invalidLevelResponse.Status,
                forgedRulesResponse.Status,
                forgedHttpModeResponse.Status,
                forgedHttpModeResponse.Body,
                forgedHttpRulesResponse.Status,
                forgedHttpRulesResponse.Body,
                forgedHttpMilestoneResponse.Status,
                forgedHttpMilestoneResponse.Body,
                rankedBoardResponse.Status,
                rankedBoardResponse.Body);
            return 1;
        }

        Console.WriteLine("LEADERBOARD ELIGIBILITY RESULT 0 failures (server level/build snapshots, HTTP scope/ruleset, eligible and ineligible submissions, player-level partitions)");
        return 0;
    }
}
