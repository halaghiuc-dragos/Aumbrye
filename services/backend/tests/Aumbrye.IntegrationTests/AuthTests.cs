using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Aumbrye.Shared.Contracts.Auth;
using Aumbrye.Shared.Contracts.Leaderboards;

namespace Aumbrye.IntegrationTests;

public class AuthTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;

    public AuthTests(AumbryeWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ClientVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedClientVersion);
        _client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ContentVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedContentVersion);
    }

    [Fact]
    public async Task Logout_ThenRefresh_ReturnsUnauthorized()
    {
        var email = $"auth_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);

        var logoutRequest = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/logout");
        logoutRequest.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.Tokens.AccessToken);
        logoutRequest.Content = JsonContent.Create(new LogoutRequest(auth.Tokens.RefreshToken));
        var logout = await _client.SendAsync(logoutRequest);
        Assert.Equal(HttpStatusCode.NoContent, logout.StatusCode);

        var refresh = await _client.PostAsJsonAsync(
            "/api/v1/auth/refresh",
            new RefreshRequest(auth.Tokens.RefreshToken));
        Assert.Equal(HttpStatusCode.Unauthorized, refresh.StatusCode);
    }

    [Fact]
    public async Task ReusedRefreshToken_RevokesFamily()
    {
        var email = $"family_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        var originalRefresh = auth.Tokens.RefreshToken;

        var firstRefresh = await _client.PostAsJsonAsync(
            "/api/v1/auth/refresh",
            new RefreshRequest(originalRefresh));
        var firstBody = await firstRefresh.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(firstBody);

        var reuse = await _client.PostAsJsonAsync(
            "/api/v1/auth/refresh",
            new RefreshRequest(originalRefresh));
        Assert.Equal(HttpStatusCode.Unauthorized, reuse.StatusCode);

        var newest = await _client.PostAsJsonAsync(
            "/api/v1/auth/refresh",
            new RefreshRequest(firstBody.Tokens.RefreshToken));
        Assert.Equal(HttpStatusCode.Unauthorized, newest.StatusCode);
    }
}
