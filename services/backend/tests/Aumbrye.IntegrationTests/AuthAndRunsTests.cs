using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Aumbrye.Application.Abstractions;
using Aumbrye.IntegrationTests.TestDoubles;
using Aumbrye.Shared.Contracts;
using Aumbrye.Shared.Contracts.Auth;
using Aumbrye.Shared.Contracts.Runs;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Aumbrye.IntegrationTests;

public class AumbryeWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<IDungeonGenerator>();
            services.AddSingleton<IDungeonGenerator, CountingDungeonGenerator>();
        });
    }
}

public class AuthIntegrationTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;

    public AuthIntegrationTests(AumbryeWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
        AddVersionHeaders(_client);
    }

    [Fact]
    public async Task Register_Login_Refresh_Succeeds()
    {
        var email = $"user_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        Assert.Equal(HttpStatusCode.OK, register.StatusCode);

        var login = await _client.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest(email, "password123"));
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        var loginBody = await login.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(loginBody);

        var refresh = await _client.PostAsJsonAsync("/api/v1/auth/refresh",
            new RefreshRequest(loginBody.Tokens.RefreshToken));
        Assert.Equal(HttpStatusCode.OK, refresh.StatusCode);
    }

    [Fact]
    public async Task Login_InvalidCredentials_ReturnsUnauthorized()
    {
        var response = await _client.PostAsJsonAsync("/api/v1/auth/login",
            new LoginRequest("nobody@test.local", "wrongpassword"));
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task MismatchedClientVersion_Returns426()
    {
        var client = _client;
        var req = new HttpRequestMessage(HttpMethod.Get, "/api/v1/leaderboards");
        req.Headers.Add(ApiVersions.ClientVersionHeader, "0.0.1");
        req.Headers.Add(ApiVersions.ContentVersionHeader, ApiVersions.ExpectedContentVersion);
        var response = await client.SendAsync(req);
        Assert.Equal((HttpStatusCode)426, response.StatusCode);
    }

    [Fact]
    public async Task MismatchedClientVersion_DoesNotGateHealthProbes()
    {
        // Orchestration probes are long-lived and may still carry the previous release's headers
        // right after a deploy. Gating them would flap the rollout for a non-health reason.
        var req = new HttpRequestMessage(HttpMethod.Get, "/api/v1/health");
        req.Headers.Add(ApiVersions.ClientVersionHeader, "0.0.1");
        req.Headers.Add(ApiVersions.ContentVersionHeader, "0.0.1");

        var response = await _client.SendAsync(req);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private static void AddVersionHeaders(HttpClient client)
    {
        client.DefaultRequestHeaders.Add(ApiVersions.ClientVersionHeader, ApiVersions.ExpectedClientVersion);
        client.DefaultRequestHeaders.Add(ApiVersions.ContentVersionHeader, ApiVersions.ExpectedContentVersion);
    }
}

public class RunsIntegrationTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly AumbryeWebApplicationFactory _factory;

    public RunsIntegrationTests(AumbryeWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Add(ApiVersions.ClientVersionHeader, ApiVersions.ExpectedClientVersion);
        _client.DefaultRequestHeaders.Add(ApiVersions.ContentVersionHeader, ApiVersions.ExpectedContentVersion);
    }

    [Fact]
    public async Task CreateRun_GetDungeon_CompleteRun_Flow()
    {
        var email = $"runner_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);

        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.Tokens.AccessToken);

        var create = await _client.PostAsJsonAsync("/api/v1/runs",
            new CreateRunRequest("forgotten_castle", Seed: 4242, Tier: 1));
        Assert.Equal(HttpStatusCode.OK, create.StatusCode);
        var run = await create.Content.ReadFromJsonAsync<CreateRunResponse>();
        Assert.NotNull(run);
        Assert.Contains("forgotten_castle", run.DefinitionJson);

        var dungeon = await _client.GetAsync($"/api/v1/runs/{run.RunId}/dungeon");
        Assert.Equal(HttpStatusCode.OK, dungeon.StatusCode);
        var dungeonJson = await dungeon.Content.ReadAsStringAsync();
        Assert.Equal(run.DefinitionJson, dungeonJson);

        await TestDoubles.RunClockHelper.BackdateAsync(
            _factory.Services, run.RunId, TimeSpan.FromMinutes(3));

        var complete = await _client.PostAsJsonAsync($"/api/v1/runs/{run.RunId}/complete",
            new CompleteRunRequest("escaped", 120, true, []));
        Assert.Equal(HttpStatusCode.OK, complete.StatusCode);

        // Completion is idempotent: a client that retries after a timeout gets the original
        // result back rather than a second progression grant or a spurious error.
        var doubleComplete = await _client.PostAsJsonAsync($"/api/v1/runs/{run.RunId}/complete",
            new CompleteRunRequest("escaped", 120, true, []));
        Assert.Equal(HttpStatusCode.OK, doubleComplete.StatusCode);

        var first = await complete.Content.ReadFromJsonAsync<CompleteRunResponse>();
        var replayed = await doubleComplete.Content.ReadFromJsonAsync<CompleteRunResponse>();
        Assert.NotNull(first?.Progression);
        Assert.NotNull(replayed?.Progression);
        Assert.Equal(first.Progression.TotalXp, replayed.Progression.TotalXp);
        Assert.Equal(first.Progression.XpGained, replayed.Progression.XpGained);
    }

    [Fact]
    public async Task CreateRun_UnknownBiome_ReturnsBadRequest()
    {
        var email = $"runner_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.Tokens.AccessToken);

        var create = await _client.PostAsJsonAsync("/api/v1/runs",
            new CreateRunRequest("unknown_biome", Seed: 1, Tier: 1));
        Assert.Equal(HttpStatusCode.BadRequest, create.StatusCode);
    }

    [Fact]
    public async Task CompleteRun_EscapeWithoutBoss_ReturnsBadRequest()
    {
        var email = $"runner_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.Tokens.AccessToken);

        var create = await _client.PostAsJsonAsync("/api/v1/runs",
            new CreateRunRequest("forgotten_castle", Seed: 99, Tier: 1));
        var run = await create.Content.ReadFromJsonAsync<CreateRunResponse>();
        Assert.NotNull(run);

        var complete = await _client.PostAsJsonAsync($"/api/v1/runs/{run.RunId}/complete",
            new CompleteRunRequest("escaped", 60, false, []));
        Assert.Equal(HttpStatusCode.BadRequest, complete.StatusCode);
    }

    [Fact]
    public async Task GetDungeon_SecondRequestUsesCacheWithoutRegeneration()
    {
        var generator = (CountingDungeonGenerator)_factory.Services.GetRequiredService<IDungeonGenerator>();
        generator.Reset();

        var email = $"runner_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.Tokens.AccessToken);

        var create = await _client.PostAsJsonAsync("/api/v1/runs",
            new CreateRunRequest("forgotten_castle", Seed: 42_001, Tier: 1));
        Assert.Equal(HttpStatusCode.OK, create.StatusCode);
        var run = await create.Content.ReadFromJsonAsync<CreateRunResponse>();
        Assert.NotNull(run);
        Assert.Equal(1, generator.GenerateCallCount);

        var first = await _client.GetAsync($"/api/v1/runs/{run.RunId}/dungeon");
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(1, generator.GenerateCallCount);

        var second = await _client.GetAsync($"/api/v1/runs/{run.RunId}/dungeon");
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.Equal(1, generator.GenerateCallCount);
    }

    [Fact]
    public async Task CompleteRun_UnknownLootId_ReturnsBadRequest()
    {
        var email = $"runner_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.Tokens.AccessToken);

        var create = await _client.PostAsJsonAsync("/api/v1/runs",
            new CreateRunRequest("forgotten_castle", Seed: 55, Tier: 1));
        var run = await create.Content.ReadFromJsonAsync<CreateRunResponse>();
        Assert.NotNull(run);

        var complete = await _client.PostAsJsonAsync($"/api/v1/runs/{run.RunId}/complete",
            new CompleteRunRequest("escaped", 90, true, [Guid.NewGuid().ToString()]));
        Assert.Equal(HttpStatusCode.BadRequest, complete.StatusCode);
    }
}
