using System.Net;
using System.Net.Http.Json;
using Aumbrye.Infrastructure.Security;
using Aumbrye.Shared.Contracts;
using Microsoft.AspNetCore.Hosting;
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

    [Fact]
    public async Task Health_RespondsUnderProductionEnvironment()
    {
        Environment.SetEnvironmentVariable("ASPNETCORE_ENVIRONMENT", "Production");
        Environment.SetEnvironmentVariable("Jwt__Secret", "integration-test-jwt-secret-32chars!!");
        Environment.SetEnvironmentVariable("UseInMemoryStores", "true");

        try
        {
            using var factory = new WebApplicationFactory<Program>()
                .WithWebHostBuilder(builder => builder.UseEnvironment("Production"));
            using var client = factory.CreateClient();
            client.DefaultRequestHeaders.Add(ApiVersions.ClientVersionHeader, ApiVersions.ExpectedClientVersion);
            client.DefaultRequestHeaders.Add(ApiVersions.ContentVersionHeader, ApiVersions.ExpectedContentVersion);

            var response = await client.GetAsync("/api/v1/health");

            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            var body = await response.Content.ReadFromJsonAsync<HealthResponse>();
            Assert.NotNull(body);
            Assert.Equal("ok", body.Status);
        }
        finally
        {
            Environment.SetEnvironmentVariable("ASPNETCORE_ENVIRONMENT", null);
            Environment.SetEnvironmentVariable("Jwt__Secret", null);
            Environment.SetEnvironmentVariable("UseInMemoryStores", null);
        }
    }
}
