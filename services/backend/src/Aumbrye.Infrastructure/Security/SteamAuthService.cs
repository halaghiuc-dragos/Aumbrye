using System.Net.Http.Json;
using System.Text.Json;
using Aumbrye.Application.Abstractions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace Aumbrye.Infrastructure.Security;

public sealed class SteamAuthService : ISteamAuthService
{
    private readonly HttpClient _http;
    private readonly string? _webApiKey;
    private readonly ILogger<SteamAuthService> _logger;

    public SteamAuthService(HttpClient http, IConfiguration configuration, ILogger<SteamAuthService> logger)
    {
        _http = http;
        _logger = logger;
        _webApiKey = configuration["Steam:WebApiKey"];
    }

    public bool IsConfigured => !string.IsNullOrWhiteSpace(_webApiKey);

    public async Task<SteamTicketValidation> ValidateAsync(string ticketHex, uint appId, CancellationToken ct = default)
    {
        if (!IsConfigured)
            return new SteamTicketValidation(false, Error: "Steam authentication is not configured.");

        var url =
            $"https://partner.steam-api.com/ISteamUserAuth/AuthenticateUserTicket/v1/?key={Uri.EscapeDataString(_webApiKey!)}&appid={appId}&ticket={Uri.EscapeDataString(ticketHex)}&identity=aumbrye";

        try
        {
            using var response = await _http.GetAsync(url, ct);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning("Steam API returned {StatusCode}", response.StatusCode);
                return new SteamTicketValidation(false, Error: "Steam is unavailable.");
            }

            await using var stream = await response.Content.ReadAsStreamAsync(ct);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
            var root = document.RootElement;
            if (!root.TryGetProperty("response", out var responseNode))
                return new SteamTicketValidation(false, Error: "Steam rejected the ticket.");
            if (!responseNode.TryGetProperty("params", out var parameters))
                return new SteamTicketValidation(false, Error: "Steam rejected the ticket.");

            var result = parameters.GetProperty("result").GetString();
            if (!string.Equals(result, "OK", StringComparison.OrdinalIgnoreCase))
                return new SteamTicketValidation(false, Error: "Steam rejected the ticket.");

            var vacBanned = parameters.TryGetProperty("vacbanned", out var vacNode) && vacNode.GetBoolean();
            var publisherBanned = parameters.TryGetProperty("publisherbanned", out var pubNode) && pubNode.GetBoolean();
            if (!parameters.TryGetProperty("steamid", out var steamIdNode))
                return new SteamTicketValidation(false, Error: "Steam rejected the ticket.");

            if (!ulong.TryParse(steamIdNode.GetString(), out var steamId))
                return new SteamTicketValidation(false, Error: "Steam rejected the ticket.");

            return new SteamTicketValidation(true, steamId, vacBanned, publisherBanned);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            _logger.LogWarning(ex, "Steam ticket validation failed");
            return new SteamTicketValidation(false, Error: "Steam is unavailable.");
        }
    }
}
