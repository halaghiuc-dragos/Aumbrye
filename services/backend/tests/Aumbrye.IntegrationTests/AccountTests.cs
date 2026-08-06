using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Aumbrye.Infrastructure.Persistence;
using Aumbrye.Shared.Contracts.Auth;
using Microsoft.Extensions.DependencyInjection;

namespace Aumbrye.IntegrationTests;

public class HealthReadyTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;

    public HealthReadyTests(AumbryeWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Add(
            Aumbrye.Shared.Contracts.ApiVersions.ClientVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedClientVersion);
    }

    [Fact]
    public async Task Ready_InTesting_Returns200()
    {
        var response = await _client.GetAsync("/api/v1/health/ready");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}

public class AccountTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly AumbryeWebApplicationFactory _factory;

    public AccountTests(AumbryeWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ClientVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedClientVersion);
        _client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ContentVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedContentVersion);
    }

    [Fact]
    public async Task Delete_RemovesRunsTokensAndSave()
    {
        var email = $"del_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.Tokens.AccessToken);

        var create = await _client.PostAsJsonAsync(
            "/api/v1/runs",
            new Aumbrye.Shared.Contracts.Runs.CreateRunRequest("forgotten_castle", Seed: 1, Tier: 1));
        Assert.Equal(HttpStatusCode.OK, create.StatusCode);

        var delete = await _client.DeleteAsync("/api/v1/account");
        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AumbryeDbContext>();
        Assert.Null(await db.Accounts.FindAsync(auth.User.Id));
        Assert.Empty(db.Runs.Where(r => r.AccountId == auth.User.Id));
        Assert.Empty(db.RefreshTokens.Where(t => t.AccountId == auth.User.Id));
        Assert.Null(await db.SaveBlobs.FindAsync(auth.User.Id));
    }
}
