using System.Net;
using Aumbrye.Shared.Contracts;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Aumbrye.IntegrationTests;

public class CorsTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;

    public CorsTests(AumbryeWebApplicationFactory factory) => _client = factory.CreateClient();

    [Fact]
    public async Task Preflight_FromAllowedOrigin_ReturnsAllowOriginHeader()
    {
        var request = new HttpRequestMessage(HttpMethod.Options, "/api/v1/auth/login");
        request.Headers.Add("Origin", "http://localhost:5173");
        request.Headers.Add("Access-Control-Request-Method", "POST");
        request.Headers.Add("Access-Control-Request-Headers", "content-type");

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Equal("http://localhost:5173", response.Headers.GetValues("Access-Control-Allow-Origin").Single());
    }

    [Fact]
    public async Task Preflight_FromUnknownOrigin_OmitsAllowOrigin()
    {
        var request = new HttpRequestMessage(HttpMethod.Options, "/api/v1/auth/login");
        request.Headers.Add("Origin", "http://evil.example");
        request.Headers.Add("Access-Control-Request-Method", "POST");

        var response = await _client.SendAsync(request);

        Assert.False(response.Headers.Contains("Access-Control-Allow-Origin"));
    }

    [Fact]
    public async Task Preflight_WithoutVersionHeaders_IsNotRejectedWith426()
    {
        var request = new HttpRequestMessage(HttpMethod.Options, "/api/v1/auth/login");
        request.Headers.Add("Origin", "http://localhost:5173");
        request.Headers.Add("Access-Control-Request-Method", "POST");

        var response = await _client.SendAsync(request);

        Assert.NotEqual((HttpStatusCode)426, response.StatusCode);
    }
}
