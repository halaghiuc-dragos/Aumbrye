using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Aumbrye.Shared.Contracts.Auth;
using Aumbrye.Shared.Contracts.Runs;

namespace Aumbrye.IntegrationTests;

public class RateLimitTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;

    public RateLimitTests(AumbryeWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ClientVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedClientVersion);
        _client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ContentVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedContentVersion);
    }

    [Fact]
    public async Task RunsGroup_EleventhRequestInWindow_Returns429()
    {
        var email = $"rate_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync(
            "/api/v1/auth/register",
            new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.Tokens.AccessToken);

        HttpStatusCode? lastStatus = null;
        for (var i = 0; i < 11; i++)
        {
            var response = await _client.PostAsJsonAsync(
                "/api/v1/runs",
                new CreateRunRequest("forgotten_castle", Seed: 100 + i, Tier: 1));
            lastStatus = response.StatusCode;
            if (response.StatusCode == HttpStatusCode.TooManyRequests)
                break;
        }

        Assert.Equal(HttpStatusCode.TooManyRequests, lastStatus);
    }
}
