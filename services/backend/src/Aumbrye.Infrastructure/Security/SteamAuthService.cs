using System.Text.Json;
using Aumbrye.Application.Abstractions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace Aumbrye.Infrastructure.Security;

public sealed class SteamAuthService : ISteamAuthService
{
    /// <summary>Named <see cref="HttpClient"/> registration used for Steam partner API calls.</summary>
    public const string HttpClientName = "steam";

    private const string AuthenticateUserTicketUrl =
        "https://partner.steam-api.com/ISteamUserAuth/AuthenticateUserTicket/v1/";

    private readonly IHttpClientFactory _httpFactory;
    private readonly string? _webApiKey;
    private readonly ILogger<SteamAuthService> _logger;

    public SteamAuthService(
        IHttpClientFactory httpFactory,
        IConfiguration configuration,
        ILogger<SteamAuthService> logger)
    {
        _httpFactory = httpFactory;
        _logger = logger;
        _webApiKey = configuration["Steam:WebApiKey"];
        ConfiguredAppId = configuration.GetValue<uint?>("Steam:AppId");
        RequireOwnSteamId = configuration.GetValue<bool?>("Steam:RejectFamilySharing") ?? true;
    }

    public bool IsConfigured => !string.IsNullOrWhiteSpace(_webApiKey);

    /// <summary>
    /// The app id this deployment issues accounts for. Tickets are only ever validated against
    /// this value — a client-supplied app id is never forwarded to Steam, because a ticket minted
    /// for any other app the attacker owns would otherwise validate successfully.
    /// </summary>
    public uint? ConfiguredAppId { get; }

    /// <summary>When true, a family-shared session (ownersteamid != steamid) is rejected.</summary>
    public bool RequireOwnSteamId { get; }

    public async Task<SteamTicketValidation> ValidateAsync(string ticketHex, uint appId, CancellationToken ct = default)
    {
        if (!IsConfigured)
            return new SteamTicketValidation(false, Error: "Steam authentication is not configured.");

        // The key travels in a POST body rather than the query string so it never lands in proxy
        // access logs or OpenTelemetry's recorded request URLs.
        using var content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["key"] = _webApiKey!,
            ["appid"] = appId.ToString(),
            ["ticket"] = ticketHex,
            ["identity"] = "aumbrye",
        });

        try
        {
            var http = _httpFactory.CreateClient(HttpClientName);
            using var response = await http.PostAsync(AuthenticateUserTicketUrl, content, ct);
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

            if (RequireOwnSteamId
                && parameters.TryGetProperty("ownersteamid", out var ownerNode)
                && ulong.TryParse(ownerNode.GetString(), out var ownerSteamId)
                && ownerSteamId != steamId)
            {
                _logger.LogInformation("Rejecting family-shared Steam session for {SteamId}.", steamId);
                return new SteamTicketValidation(false, Error: "Family-shared copies cannot create accounts.");
            }

            return new SteamTicketValidation(true, steamId, vacBanned, publisherBanned);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            _logger.LogWarning(ex, "Steam ticket validation failed");
            return new SteamTicketValidation(false, Error: "Steam is unavailable.");
        }
    }
}
