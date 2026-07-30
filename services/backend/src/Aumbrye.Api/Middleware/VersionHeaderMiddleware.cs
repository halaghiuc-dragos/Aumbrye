using Aumbrye.Shared.Contracts;

namespace Aumbrye.Api.Middleware;

public class VersionHeaderMiddleware
{
    private readonly RequestDelegate _next;

    public VersionHeaderMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context)
    {
        if (context.Request.Path.StartsWithSegments("/api"))
        {
            var clientVersion = context.Request.Headers[ApiVersions.ClientVersionHeader].FirstOrDefault();
            var contentVersion = context.Request.Headers[ApiVersions.ContentVersionHeader].FirstOrDefault();

            if (!string.IsNullOrEmpty(clientVersion) &&
                !string.Equals(clientVersion, ApiVersions.ExpectedClientVersion, StringComparison.Ordinal))
            {
                context.Response.StatusCode = StatusCodes.Status426UpgradeRequired;
                await context.Response.WriteAsJsonAsync(new
                {
                    error = $"Unsupported client version '{clientVersion}'. Expected '{ApiVersions.ExpectedClientVersion}'.",
                });
                return;
            }

            if (!string.IsNullOrEmpty(contentVersion) &&
                !string.Equals(contentVersion, ApiVersions.ExpectedContentVersion, StringComparison.Ordinal))
            {
                context.Response.StatusCode = StatusCodes.Status400BadRequest;
                await context.Response.WriteAsJsonAsync(new
                {
                    error = $"Unsupported content version '{contentVersion}'. Expected '{ApiVersions.ExpectedContentVersion}'.",
                });
                return;
            }
        }

        await _next(context);
    }
}
