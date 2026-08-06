using System.Net;
using System.Net.Http.Json;
using Aumbrye.Application.Abstractions;
using Aumbrye.Domain.Entities;
using Aumbrye.Infrastructure.Persistence;
using Aumbrye.IntegrationTests.TestDoubles;
using Aumbrye.Shared.Contracts;
using Aumbrye.Shared.Contracts.Auth;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Aumbrye.IntegrationTests;

public sealed class FakeSteamAuthService : ISteamAuthService
{
    public bool IsConfigured { get; set; } = true;
    public SteamTicketValidation NextValidation { get; set; } =
        new(true, SteamId: 76561198000000001UL);

    public Task<SteamTicketValidation> ValidateAsync(string ticketHex, uint appId, CancellationToken ct = default)
    {
        _ = ticketHex;
        _ = appId;
        return Task.FromResult(NextValidation);
    }
}

public class SteamAuthWebApplicationFactory : WebApplicationFactory<Program>
{
    public FakeSteamAuthService FakeSteam { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<IDungeonGenerator>();
            services.AddSingleton<IDungeonGenerator, CountingDungeonGenerator>();
            services.RemoveAll<ISteamAuthService>();
            services.AddSingleton<ISteamAuthService>(FakeSteam);
        });
    }
}

public class SteamAuthTests : IClassFixture<SteamAuthWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly SteamAuthWebApplicationFactory _factory;

    public SteamAuthTests(SteamAuthWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Add(ApiVersions.ClientVersionHeader, ApiVersions.ExpectedClientVersion);
        _client.DefaultRequestHeaders.Add(ApiVersions.ContentVersionHeader, ApiVersions.ExpectedContentVersion);
        _factory.FakeSteam.IsConfigured = true;
        _factory.FakeSteam.NextValidation = new SteamTicketValidation(true, 76561198000000001UL);
    }

    [Fact]
    public async Task SteamAuth_ValidTicket_CreatesAccountAndReturnsTokens()
    {
        var response = await _client.PostAsJsonAsync(
            "/api/v1/auth/steam",
            new SteamAuthRequest("deadbeef", 480U));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(body);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AumbryeDbContext>();
        var account = await db.Accounts.FirstAsync(a => a.SteamId == 76561198000000001UL);
        Assert.Null(account.Email);
    }

    [Fact]
    public async Task SteamAuth_ValidTicketForExistingSteamId_ReturnsSameAccount()
    {
        var first = await _client.PostAsJsonAsync(
            "/api/v1/auth/steam",
            new SteamAuthRequest("cafebabe", 480U));
        var firstBody = await first.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(firstBody);

        var second = await _client.PostAsJsonAsync(
            "/api/v1/auth/steam",
            new SteamAuthRequest("cafebabe", 480U));
        var secondBody = await second.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(secondBody);
        Assert.Equal(firstBody.User.Id, secondBody.User.Id);

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AumbryeDbContext>();
        Assert.Equal(1, await db.Accounts.CountAsync(a => a.SteamId == 76561198000000001UL));
    }

    [Fact]
    public async Task SteamAuth_RejectedTicket_ReturnsUnauthorized()
    {
        _factory.FakeSteam.IsConfigured = true;
        _factory.FakeSteam.NextValidation = new SteamTicketValidation(false, Error: "Steam rejected the ticket.");
        var response = await _client.PostAsJsonAsync(
            "/api/v1/auth/steam",
            new SteamAuthRequest("deadbeef00", 480U));
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task SteamAuth_BannedAccount_ReturnsUnauthorized()
    {
        _factory.FakeSteam.NextValidation = new SteamTicketValidation(
            true, 76561198000000002UL, VacBanned: true);
        var response = await _client.PostAsJsonAsync(
            "/api/v1/auth/steam",
            new SteamAuthRequest("banned", 480U));
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task SteamAuth_MissingWebApiKey_ReturnsServiceUnavailable()
    {
        _factory.FakeSteam.IsConfigured = false;
        var response = await _client.PostAsJsonAsync(
            "/api/v1/auth/steam",
            new SteamAuthRequest("deadbeef", 480U));
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);

        var email = $"steam_off_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        Assert.Equal(HttpStatusCode.OK, register.StatusCode);
        var login = await _client.PostAsJsonAsync(
            "/api/v1/auth/login",
            new LoginRequest(email, "password123"));
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
    }

    [Fact]
    public async Task LinkSteam_AlreadyLinkedToAnotherAccount_ReturnsConflict()
    {
        var steamLogin = await _client.PostAsJsonAsync(
            "/api/v1/auth/steam",
            new SteamAuthRequest("linked", 480U));
        var steamAuth = await steamLogin.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(steamAuth);

        var email = $"link_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var emailAuth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(emailAuth);

        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", emailAuth.Tokens.AccessToken);
        var link = await _client.PostAsJsonAsync(
            "/api/v1/account/link-steam",
            new LinkSteamRequest("linked", 480U));
        Assert.Equal(HttpStatusCode.Conflict, link.StatusCode);
    }
}
