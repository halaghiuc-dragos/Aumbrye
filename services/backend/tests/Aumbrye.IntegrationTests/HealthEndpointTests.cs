using System.Net;
using System.Net.Http.Json;
using Aumbrye.Shared.Contracts;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Aumbrye.IntegrationTests;

public class HealthEndpointTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;

    public HealthEndpointTests(AumbryeWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ClientVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedClientVersion);
        _client.DefaultRequestHeaders.Add(Aumbrye.Shared.Contracts.ApiVersions.ContentVersionHeader,
            Aumbrye.Shared.Contracts.ApiVersions.ExpectedContentVersion);
    }

    [Fact]
    public async Task GetHealth_ReturnsOkWithStatus()
    {
        var response = await _client.GetAsync("/api/v1/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<HealthResponse>();
        Assert.NotNull(body);
        Assert.Equal("ok", body.Status);
    }
}
