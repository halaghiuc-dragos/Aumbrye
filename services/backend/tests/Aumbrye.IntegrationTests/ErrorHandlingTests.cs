using System.Net;
using System.Text.Json;

namespace Aumbrye.IntegrationTests;

public class ErrorHandlingTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;

    public ErrorHandlingTests(AumbryeWebApplicationFactory factory) => _client = factory.CreateClient();

    [Fact]
    public async Task UnhandledException_ReturnsProblemDetails()
    {
        var response = await _client.GetAsync("/api/v1/__test/throw");

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        Assert.Contains("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var body = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain("at ", body);
        using var doc = JsonDocument.Parse(body);
        Assert.True(doc.RootElement.TryGetProperty("traceId", out var traceId));
        Assert.False(string.IsNullOrWhiteSpace(traceId.GetString()));
    }
}
