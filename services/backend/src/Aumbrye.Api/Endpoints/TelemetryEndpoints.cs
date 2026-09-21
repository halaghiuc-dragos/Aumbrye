using System.Text.Json;

namespace Aumbrye.Api.Auth;

public static class TelemetryEndpoints
{
    private const int MaxKindLength = 80;
    private const int MaxMessageLength = 1_000;
    private const int MaxStackLength = 8_000;
    private const int MaxMetadataLength = 128;

    public static RouteGroupBuilder MapTelemetryEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/telemetry").WithTags("Telemetry");

        group.MapPost("/crash", async (JsonElement report, ILoggerFactory loggerFactory, CancellationToken ct) =>
        {
            _ = ct;
            if (report.ValueKind != JsonValueKind.Object)
                return Results.BadRequest(new { error = "Crash report must be an object." });

            var logger = loggerFactory.CreateLogger("CrashTelemetry");
            var kind = ReadField(report, "kind", MaxKindLength);
            var message = ReadField(report, "message", MaxMessageLength);
            var stack = ReadField(report, "stack", MaxStackLength);
            var version = ReadField(report, "version", MaxMetadataLength);
            var platform = ReadField(report, "platform", MaxMetadataLength);
            logger.LogWarning(
                "Client crash received. Kind: {Kind}; Message: {Message}; Stack: {Stack}; Version: {Version}; Platform: {Platform}",
                kind, message, stack, version, platform);
            return Results.NoContent();
        })
        .WithName("CrashTelemetry")
        .RequireRateLimiting("telemetry")
        .Produces(StatusCodes.Status204NoContent);

        return group;
    }

    private static string ReadField(JsonElement report, string name, int maxLength)
    {
        if (!report.TryGetProperty(name, out var field) || field.ValueKind != JsonValueKind.String)
            return string.Empty;

        var value = field.GetString() ?? string.Empty;
        return value.Length <= maxLength ? value : value[..maxLength];
    }
}
