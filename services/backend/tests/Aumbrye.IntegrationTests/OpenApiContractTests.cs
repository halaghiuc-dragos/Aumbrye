using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using Aumbrye.Shared.Contracts;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Aumbrye.IntegrationTests;

public class OpenApiContractTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;

    public OpenApiContractTests(AumbryeWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task SwaggerJson_ContainsSamePathsAsCommittedYaml()
    {
        var swaggerResponse = await _client.GetAsync("/swagger/v1/swagger.json");
        Assert.Equal(HttpStatusCode.OK, swaggerResponse.StatusCode);
        var swaggerJson = await swaggerResponse.Content.ReadAsStringAsync();
        var swagger = JsonNode.Parse(swaggerJson)!.AsObject();
        var swaggerPaths = swagger["paths"]!.AsObject().Select(static p => p.Key).ToHashSet(StringComparer.Ordinal);

        var yamlPath = FindCommittedOpenApiYaml();
        var yamlPaths = ExtractPathsFromYaml(File.ReadAllLines(yamlPath)).ToHashSet(StringComparer.Ordinal);

        Assert.Equal(yamlPaths, swaggerPaths);
    }

    private static string FindCommittedOpenApiYaml()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            var candidate = Path.Combine(dir.FullName, "packages", "shared", "openapi", "aumbrye-api.v1.yaml");
            if (File.Exists(candidate))
                return candidate;
            dir = dir.Parent;
        }

        throw new InvalidOperationException("Committed OpenAPI YAML not found.");
    }

    private static IEnumerable<string> ExtractPathsFromYaml(IEnumerable<string> lines)
    {
        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith("/api/v1/", StringComparison.Ordinal))
            {
                yield return trimmed.TrimEnd(':');
                continue;
            }

            if (trimmed.StartsWith("'/api/v1/", StringComparison.Ordinal) ||
                trimmed.StartsWith("\"/api/v1/", StringComparison.Ordinal))
            {
                yield return trimmed.Trim('\'', '"', ':');
            }
        }
    }
}
