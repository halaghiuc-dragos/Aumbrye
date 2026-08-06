using System.Text.Json;

namespace Aumbrye.Api.Auth;

public static class TelemetryEndpoints
{
    public static RouteGroupBuilder MapTelemetryEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/telemetry").WithTags("Telemetry");

        group.MapPost("/crash", async (JsonElement report, ILoggerFactory loggerFactory, CancellationToken ct) =>
        {
            _ = ct;
            var logger = loggerFactory.CreateLogger("CrashTelemetry");
            logger.LogInformation("Crash report received: {Report}", report.GetRawText());
            return Results.NoContent();
        })
        .WithName("CrashTelemetry")
        .Produces(StatusCodes.Status204NoContent);

        return group;
    }
}
