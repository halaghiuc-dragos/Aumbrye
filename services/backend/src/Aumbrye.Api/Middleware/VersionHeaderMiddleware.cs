using Aumbrye.Shared.Contracts;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;

namespace Aumbrye.Api.Middleware;

public class VersionHeaderMiddleware
{
    /// <summary>
    /// Health endpoints are exempt from version gating. Orchestration probes are long-lived and
    /// may still be sending the previous release's headers moments after a deploy; failing their
    /// checks would flap the rollout for a reason that has nothing to do with service health.
    /// </summary>
    private const string HealthPathPrefix = "/api/v1/health";

    private readonly RequestDelegate _next;
    private readonly IProblemDetailsService _problemDetails;

    public VersionHeaderMiddleware(RequestDelegate next, IProblemDetailsService problemDetails)
    {
        _next = next;
        _problemDetails = problemDetails;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        if (HttpMethods.IsOptions(context.Request.Method))
        {
            await _next(context);
            return;
        }

        if (context.Request.Path.StartsWithSegments("/api")
            && !context.Request.Path.StartsWithSegments(HealthPathPrefix))
        {
            var clientVersion = context.Request.Headers[ApiVersions.ClientVersionHeader].FirstOrDefault();
            var contentVersion = context.Request.Headers[ApiVersions.ContentVersionHeader].FirstOrDefault();

            if (!string.IsNullOrEmpty(clientVersion) &&
                !string.Equals(clientVersion, ApiVersions.ExpectedClientVersion, StringComparison.Ordinal))
            {
                await WriteProblemAsync(
                    context,
                    StatusCodes.Status426UpgradeRequired,
                    "Upgrade Required",
                    $"Unsupported client version '{clientVersion}'. Expected '{ApiVersions.ExpectedClientVersion}'.");
                return;
            }

            if (!string.IsNullOrEmpty(contentVersion) &&
                !string.Equals(contentVersion, ApiVersions.ExpectedContentVersion, StringComparison.Ordinal))
            {
                await WriteProblemAsync(
                    context,
                    StatusCodes.Status400BadRequest,
                    "Bad Request",
                    $"Unsupported content version '{contentVersion}'. Expected '{ApiVersions.ExpectedContentVersion}'.");
                return;
            }
        }

        await _next(context);
    }

    /// <summary>
    /// Emits through the app's registered problem-details writer so these responses honour content
    /// negotiation and the same customizations every other error path uses, instead of hand-rolling
    /// a payload with hardcoded httpstatuses.com type URLs.
    /// </summary>
    private async Task WriteProblemAsync(HttpContext context, int statusCode, string title, string detail)
    {
        context.Response.StatusCode = statusCode;

        var written = await _problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = context,
            ProblemDetails = new ProblemDetails
            {
                Status = statusCode,
                Title = title,
                Detail = detail,
            },
        });

        if (!written)
        {
            context.Response.ContentType = "application/problem+json";
            await context.Response.WriteAsJsonAsync(new ProblemDetails
            {
                Status = statusCode,
                Title = title,
                Detail = detail,
            });
        }
    }
}
