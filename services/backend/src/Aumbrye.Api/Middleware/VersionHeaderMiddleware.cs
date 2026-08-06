using Aumbrye.Shared.Contracts;

namespace Aumbrye.Api.Middleware;

public class VersionHeaderMiddleware
{
    private readonly RequestDelegate _next;

    public VersionHeaderMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context)
    {
        if (HttpMethods.IsOptions(context.Request.Method))
        {
            await _next(context);
            return;
        }

        if (context.Request.Path.StartsWithSegments("/api"))
        {
            var clientVersion = context.Request.Headers[ApiVersions.ClientVersionHeader].FirstOrDefault();
            var contentVersion = context.Request.Headers[ApiVersions.ContentVersionHeader].FirstOrDefault();

            if (!string.IsNullOrEmpty(clientVersion) &&
                !string.Equals(clientVersion, ApiVersions.ExpectedClientVersion, StringComparison.Ordinal))
            {
                await WriteProblemAsync(
                    context,
                    StatusCodes.Status426UpgradeRequired,
                    $"Unsupported client version '{clientVersion}'. Expected '{ApiVersions.ExpectedClientVersion}'.");
                return;
            }

            if (!string.IsNullOrEmpty(contentVersion) &&
                !string.Equals(contentVersion, ApiVersions.ExpectedContentVersion, StringComparison.Ordinal))
            {
                await WriteProblemAsync(
                    context,
                    StatusCodes.Status400BadRequest,
                    $"Unsupported content version '{contentVersion}'. Expected '{ApiVersions.ExpectedContentVersion}'.");
                return;
            }
        }

        await _next(context);
    }

    private static async Task WriteProblemAsync(HttpContext context, int statusCode, string detail)
    {
        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/problem+json";
        await context.Response.WriteAsJsonAsync(new Microsoft.AspNetCore.Mvc.ProblemDetails
        {
            Status = statusCode,
            Title = statusCode == StatusCodes.Status426UpgradeRequired ? "Upgrade Required" : "Bad Request",
            Detail = detail,
            Type = $"https://httpstatuses.com/{statusCode}",
        });
    }
}
