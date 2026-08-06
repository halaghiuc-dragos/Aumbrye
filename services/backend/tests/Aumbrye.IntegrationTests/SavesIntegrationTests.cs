using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Aumbrye.Application.Abstractions;
using Aumbrye.IntegrationTests.TestDoubles;
using Aumbrye.Shared.Contracts;
using Aumbrye.Shared.Contracts.Auth;
using Aumbrye.Shared.Contracts.Saves;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Aumbrye.IntegrationTests;

public class SavesIntegrationTests : IClassFixture<AumbryeWebApplicationFactory>
{
    private readonly HttpClient _client;

    public SavesIntegrationTests(AumbryeWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Add(ApiVersions.ClientVersionHeader, ApiVersions.ExpectedClientVersion);
        _client.DefaultRequestHeaders.Add(ApiVersions.ContentVersionHeader, ApiVersions.ExpectedContentVersion);
    }

    [Fact]
    public async Task GetPutSave_RoundTrip()
    {
        await AuthenticateAsync();
        var get = await _client.GetAsync("/api/v1/saves/current");
        Assert.Equal(HttpStatusCode.OK, get.StatusCode);
        var initial = await get.Content.ReadFromJsonAsync<SaveResponse>();
        Assert.NotNull(initial);
        Assert.Contains("schemaVersion", initial.StateJson);

        var state = JsonNode.Parse(initial.StateJson)!.AsObject();
        state["character"]!["name"] = "TestHero";
        var put = await _client.PutAsJsonAsync("/api/v1/saves/current",
          new PutSaveRequest(state.ToJsonString(), initial.UpdatedAt));
        Assert.Equal(HttpStatusCode.OK, put.StatusCode);

        var get2 = await _client.GetAsync("/api/v1/saves/current");
        var saved = await get2.Content.ReadFromJsonAsync<SaveResponse>();
        Assert.NotNull(saved);
        var parsed = JsonNode.Parse(saved.StateJson)!.AsObject();
        Assert.Equal("TestHero", parsed["character"]!["name"]!.GetValue<string>());
    }

    [Fact]
    public async Task PutSave_IllegalTalent_ReturnsBadRequest()
    {
        await AuthenticateAsync();
        var get = await _client.GetAsync("/api/v1/saves/current");
        var initial = await get.Content.ReadFromJsonAsync<SaveResponse>();
        Assert.NotNull(initial);

        var state = JsonNode.Parse(initial.StateJson)!.AsObject();
        state["talents"] = new JsonObject { ["arms_2"] = 1 };
        var put = await _client.PutAsJsonAsync("/api/v1/saves/current",
          new PutSaveRequest(state.ToJsonString(), initial.UpdatedAt));
        Assert.Equal(HttpStatusCode.BadRequest, put.StatusCode);
    }

    [Fact]
    public async Task PutSave_StaleClient_ReturnsConflict()
    {
        await AuthenticateAsync();
        var get = await _client.GetAsync("/api/v1/saves/current");
        var initial = await get.Content.ReadFromJsonAsync<SaveResponse>();
        Assert.NotNull(initial);

        var state = JsonNode.Parse(initial.StateJson)!.AsObject();
        state["character"]!["name"] = "First";
        var firstPut = await _client.PutAsJsonAsync("/api/v1/saves/current",
          new PutSaveRequest(state.ToJsonString(), initial.UpdatedAt));
        Assert.Equal(HttpStatusCode.OK, firstPut.StatusCode);

        state["character"]!["name"] = "Stale";
        var conflict = await _client.PutAsJsonAsync("/api/v1/saves/current",
          new PutSaveRequest(state.ToJsonString(), initial.UpdatedAt));
        Assert.Equal(HttpStatusCode.Conflict, conflict.StatusCode);
        var conflictBody = await conflict.Content.ReadFromJsonAsync<PutSaveResponse>();
        Assert.NotNull(conflictBody);
        Assert.True(conflictBody.Conflict);
        Assert.False(string.IsNullOrWhiteSpace(conflictBody.ServerStateJson));
        Assert.Contains("schemaVersion", conflictBody.ServerStateJson);
    }

    private async Task AuthenticateAsync()
    {
        var email = $"save_{Guid.NewGuid():N}@test.local";
        var register = await _client.PostAsJsonAsync("/api/v1/auth/register",
          new RegisterRequest(email, "password123"));
        var auth = await register.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        _client.DefaultRequestHeaders.Authorization =
          new AuthenticationHeaderValue("Bearer", auth.Tokens.AccessToken);
    }
}
