using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Aumbrye.IntegrationTests.TestDoubles;
using Aumbrye.Shared.Contracts.Auth;
using Aumbrye.Shared.Contracts.Leaderboards;
using Aumbrye.Shared.Contracts.Runs;

namespace Aumbrye.IntegrationTests;

public class LeaderboardsIntegrationTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly AumbryeWebApplicationFactory _factory;

    public LeaderboardsIntegrationTests(AumbryeWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ClientVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedClientVersion);
        _client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ContentVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedContentVersion);
    }

    [Fact]
    public async Task Submit_ForCompletedRun_ReturnsRank()
    {
        await AuthenticateAsync();
        var runId = await CreateAndCompleteRunAsync();
        var response = await _client.PostAsJsonAsync(
            "/api/v1/leaderboards/submit",
            new SubmitLeaderboardRequest(runId, OptIn: true));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SubmitLeaderboardResponse>();
        Assert.NotNull(body);
        Assert.True(body.Submitted);
        Assert.True(body.Rank >= 1);
    }

    [Fact]
    public async Task Submit_OptOut_ReturnsSubmittedFalse()
    {
        await AuthenticateAsync();
        var runId = await CreateAndCompleteRunAsync();
        var response = await _client.PostAsJsonAsync(
            "/api/v1/leaderboards/submit",
            new SubmitLeaderboardRequest(runId, OptIn: false));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SubmitLeaderboardResponse>();
        Assert.NotNull(body);
        Assert.False(body.Submitted);
        Assert.Equal("opt_out", body.Reason);
    }

    [Fact]
    public async Task Submit_Unauthenticated_Returns401()
    {
        var client = _client;
        client.DefaultRequestHeaders.Authorization = null;
        var response = await client.PostAsJsonAsync(
            "/api/v1/leaderboards/submit",
            new SubmitLeaderboardRequest(Guid.NewGuid(), OptIn: true));
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Get_ReturnsSubmittedEntryOrderedByElapsed()
    {
        await AuthenticateAsync();
        var firstRun = await CreateAndCompleteRunAsync(seed: 201, elapsed: 200);
        await _client.PostAsJsonAsync(
            "/api/v1/leaderboards/submit",
            new SubmitLeaderboardRequest(firstRun, OptIn: true));

        var secondRun = await CreateAndCompleteRunAsync(seed: 202, elapsed: 90);
        await _client.PostAsJsonAsync(
            "/api/v1/leaderboards/submit",
            new SubmitLeaderboardRequest(secondRun, OptIn: true));

        var response = await _client.GetAsync("/api/v1/leaderboards?biomeId=forgotten_castle&tier=1&limit=10");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var page = await response.Content.ReadFromJsonAsync<LeaderboardPageResponse>();
        Assert.NotNull(page);
        Assert.True(page.Entries.Count >= 2);
        Assert.True(page.Entries[0].ElapsedSeconds <= page.Entries[1].ElapsedSeconds);
    }

    [Fact]
    public async Task Submit_ForOtherAccountsRun_ReturnsForbidden()
    {
        await AuthenticateAsync();
        var runId = await CreateAndCompleteRunAsync();

        var otherEmail = $"other_{Guid.NewGuid():N}@test.local";
        var otherRegister = await _client.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest(otherEmail, "password123"));
        var otherAuth = await otherRegister.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(otherAuth);
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", otherAuth.Tokens.AccessToken);

        var response = await _client.PostAsJsonAsync(
            "/api/v1/leaderboards/submit",
            new SubmitLeaderboardRequest(runId, OptIn: true));
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Submit_ForActiveRun_ReturnsBadRequest()
    {
        await AuthenticateAsync();
        var create = await _client.PostAsJsonAsync("/api/v1/runs",
            new CreateRunRequest("forgotten_castle", Seed: 42, Tier: 1));
        var run = await create.Content.ReadFromJsonAsync<CreateRunResponse>();
        Assert.NotNull(run);

        var response = await _client.PostAsJsonAsync(
            "/api/v1/leaderboards/submit",
            new SubmitLeaderboardRequest(run.RunId, OptIn: true));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Get_LimitAboveCap_ReturnsBadRequest()
    {
        var response = await _client.GetAsync("/api/v1/leaderboards?biomeId=forgotten_castle&tier=1&limit=1000");
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Get_UnknownBiome_ReturnsEmptyEntries()
    {
        var response = await _client.GetAsync("/api/v1/leaderboards?biomeId=nonexistent_biome_xyz&tier=1");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var page = await response.Content.ReadFromJsonAsync<LeaderboardPageResponse>();
        Assert.NotNull(page);
        Assert.Empty(page.Entries);
    }

    private async Task AuthenticateAsync()
    {
        var email = $"lb_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.Tokens.AccessToken);
    }

    private async Task<Guid> CreateAndCompleteRunAsync(int seed = 77, double elapsed = 120)
    {
        var create = await _client.PostAsJsonAsync("/api/v1/runs",
            new CreateRunRequest("forgotten_castle", Seed: seed, Tier: 1));
        var run = await create.Content.ReadFromJsonAsync<CreateRunResponse>();
        Assert.NotNull(run);

        // Give the run enough wall-clock history for the reported time to be plausible.
        await RunClockHelper.BackdateAsync(
            _factory.Services, run.RunId, TimeSpan.FromSeconds(elapsed + 60));

        var complete = await _client.PostAsJsonAsync($"/api/v1/runs/{run.RunId}/complete",
            new CompleteRunRequest("escaped", elapsed, true, []));
        Assert.Equal(HttpStatusCode.OK, complete.StatusCode);
        return run.RunId;
    }
}
