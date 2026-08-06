using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Aumbrye.Application.Abstractions;
using Aumbrye.Infrastructure.Persistence;
using Aumbrye.Shared.Contracts.Auth;
using Aumbrye.Shared.Contracts.Runs;
using Microsoft.Extensions.DependencyInjection;

namespace Aumbrye.IntegrationTests;

public class RunCompletionTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly AumbryeWebApplicationFactory _factory;

    public RunCompletionTests(AumbryeWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        AddVersionHeaders(_client);
    }

    [Fact]
    public async Task CompleteRun_AfterCacheEviction_AcceptsOriginalLootIds()
    {
        await AuthenticateAsync();
        var create = await _client.PostAsJsonAsync("/api/v1/runs",
            new CreateRunRequest("forgotten_castle", Seed: 9001, Tier: 1));
        var run = await create.Content.ReadFromJsonAsync<CreateRunResponse>();
        Assert.NotNull(run);

        var definition = JsonDocument.Parse(run.DefinitionJson);
        var lootId = FindFirstLootInstanceId(definition.RootElement);
        Assert.False(string.IsNullOrWhiteSpace(lootId));

        using (var scope = _factory.Services.CreateScope())
        {
            var cache = scope.ServiceProvider.GetRequiredService<IDungeonCache>();
            await cache.SetAsync(run.RunId, string.Empty, TimeSpan.Zero);
        }

        var complete = await _client.PostAsJsonAsync($"/api/v1/runs/{run.RunId}/complete",
            new CompleteRunRequest("escaped", 60, true, [lootId!]));
        Assert.Equal(HttpStatusCode.OK, complete.StatusCode);
    }

    [Fact]
    public async Task CompleteRun_CaseVariantDuplicateLootId_ReturnsBadRequest()
    {
        await AuthenticateAsync();
        var create = await _client.PostAsJsonAsync("/api/v1/runs",
            new CreateRunRequest("forgotten_castle", Seed: 9002, Tier: 1));
        var run = await create.Content.ReadFromJsonAsync<CreateRunResponse>();
        Assert.NotNull(run);

        var definition = JsonDocument.Parse(run.DefinitionJson);
        var lootId = FindFirstLootInstanceId(definition.RootElement);
        Assert.False(string.IsNullOrWhiteSpace(lootId));

        var complete = await _client.PostAsJsonAsync($"/api/v1/runs/{run.RunId}/complete",
            new CompleteRunRequest("escaped", 60, true, [lootId!, lootId!.ToUpperInvariant()]));
        Assert.Equal(HttpStatusCode.BadRequest, complete.StatusCode);
    }

    [Fact]
    public async Task CompleteRun_Abandoned_SetsAbandonedStatus()
    {
        await AuthenticateAsync();
        var create = await _client.PostAsJsonAsync("/api/v1/runs",
            new CreateRunRequest("forgotten_castle", Seed: 9003, Tier: 1));
        var run = await create.Content.ReadFromJsonAsync<CreateRunResponse>();
        Assert.NotNull(run);

        var complete = await _client.PostAsJsonAsync($"/api/v1/runs/{run.RunId}/complete",
            new CompleteRunRequest("abandoned", 30, false, []));
        Assert.Equal(HttpStatusCode.OK, complete.StatusCode);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AumbryeDbContext>();
        var stored = await db.Runs.FindAsync(run.RunId);
        Assert.NotNull(stored);
        Assert.Equal(Domain.Entities.RunStatus.Abandoned, stored.Status);
    }

    private async Task AuthenticateAsync()
    {
        var email = $"run_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync("/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.Tokens.AccessToken);
    }

    private static string? FindFirstLootInstanceId(JsonElement root)
    {
        if (!root.TryGetProperty("placements", out var placements)
            || !placements.TryGetProperty("loot", out var loot))
            return null;

        foreach (var chest in loot.EnumerateArray())
        {
            if (!chest.TryGetProperty("items", out var items))
                continue;
            foreach (var item in items.EnumerateArray())
            {
                if (item.TryGetProperty("instanceId", out var instanceId))
                    return instanceId.GetString();
            }
        }

        return null;
    }

    private static void AddVersionHeaders(HttpClient client)
    {
        client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ClientVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedClientVersion);
        client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ContentVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedContentVersion);
    }
}
