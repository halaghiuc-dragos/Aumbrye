using System.Net;
using System.Threading.RateLimiting;
using Aumbrye.Api.Auth;
using Aumbrye.Api.Middleware;
using Aumbrye.Infrastructure;
using Aumbrye.Infrastructure.Persistence;
using Aumbrye.Infrastructure.Security;
using Aumbrye.Shared.Contracts;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi;
using Npgsql;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

if (args.Contains("--healthcheck"))
{
    using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
    try
    {
        var response = await client.GetAsync("http://127.0.0.1:8080/api/v1/health");
        Environment.Exit(response.IsSuccessStatusCode ? 0 : 1);
    }
    catch
    {
        Environment.Exit(1);
    }

    return;
}

var builder = WebApplication.CreateBuilder(args);

var useInMemory = builder.Configuration.GetValue<bool>("UseInMemoryStores")
                  || builder.Environment.IsEnvironment("Testing");

var jwtKey = JwtSigningKey.FromConfiguration(builder.Configuration, useInMemory);

builder.Services.AddInfrastructure(builder.Configuration, useInMemory);

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"] ?? "aumbrye",
            ValidAudience = builder.Configuration["Jwt:Audience"] ?? "aumbrye-client",
            IssuerSigningKey = new SymmetricSecurityKey(jwtKey),
            ClockSkew = TimeSpan.FromMinutes(1),
        };
    });
builder.Services.AddAuthorization();
builder.Services.AddProblemDetails();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Aumbrye API",
        Version = "1.0.0",
        Description = "M4 gameplay loop API (auth + runs + saves + progression).",
    });
    options.AddSecurityDefinition("bearerAuth", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
    });
    options.AddSecurityRequirement(document => new OpenApiSecurityRequirement
    {
        [new OpenApiSecuritySchemeReference("bearerAuth", document, null)] = [],
    });
});

var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()
                     ?? ["http://localhost:5173"];
builder.Services.AddCors(options =>
    options.AddPolicy("web", policy => policy
        .WithOrigins(allowedOrigins)
        .WithMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
        .WithHeaders("Authorization", "Content-Type",
            ApiVersions.ClientVersionHeader, ApiVersions.ContentVersionHeader,
            Aumbrye.Shared.Contracts.Auth.AuthTransport.HeaderName)
        .WithExposedHeaders(ApiVersions.ClientVersionHeader)
        .AllowCredentials()
        .SetPreflightMaxAge(TimeSpan.FromHours(1))));

var healthChecks = builder.Services.AddHealthChecks();
if (!useInMemory)
{
    var conn = builder.Configuration.GetConnectionString("DefaultConnection");
    if (!string.IsNullOrWhiteSpace(conn))
        healthChecks.AddNpgSql(conn, name: "postgres");
    var redisConn = builder.Configuration.GetConnectionString("Redis");
    if (!string.IsNullOrWhiteSpace(redisConn))
        healthChecks.AddRedis(redisConn, name: "redis");
}

var otelEndpoint = builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"];
if (!string.IsNullOrWhiteSpace(otelEndpoint))
{
    builder.Services.AddOpenTelemetry()
        .ConfigureResource(resource => resource.AddService("Aumbrye.Api"))
        .WithTracing(tracing => tracing
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddNpgsql()
            .AddOtlpExporter())
        .WithMetrics(metrics => metrics
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddMeter("Aumbrye.Api")
            .AddOtlpExporter());
}

// Rate limits are relaxed under the in-memory/Testing configuration: the integration suite drives
// dozens of registrations and logins from one address, which is exactly what these limits exist to
// stop in production.
var authRateLimit = builder.Configuration.GetValue<int?>("RateLimits:AuthPerMinute")
                    ?? (useInMemory ? 10_000 : 30);
var registerRateLimit = builder.Configuration.GetValue<int?>("RateLimits:RegisterPerMinute")
                        ?? (useInMemory ? 10_000 : 5);

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
        RateLimitPartition.GetConcurrencyLimiter(
            "global",
            _ => new ConcurrencyLimiterOptions
            {
                PermitLimit = 200,
                QueueLimit = 0,
            }));

    options.AddFixedWindowLimiter("auth", limiter =>
    {
        limiter.PermitLimit = authRateLimit;
        limiter.Window = TimeSpan.FromMinutes(1);
        limiter.QueueLimit = 0;
    });

    // Registration answers "does this email already exist?" by design, which is acceptable for a
    // game but makes the endpoint a usable enumeration oracle. A tighter per-IP budget keeps that
    // to a trickle without hurting real sign-ups.
    options.AddPolicy("register", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            httpContext.Connection.RemoteIpAddress?.ToString() ?? "anon",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = registerRateLimit,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
            }));

    options.AddPolicy("runs", httpContext =>
    {
        var accountId = httpContext.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        return RateLimitPartition.GetFixedWindowLimiter(
            accountId ?? httpContext.Connection.RemoteIpAddress?.ToString() ?? "anon",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
            });
    });

    options.AddPolicy("saves", httpContext =>
    {
        var accountId = httpContext.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
        return RateLimitPartition.GetFixedWindowLimiter(
            accountId ?? httpContext.Connection.RemoteIpAddress?.ToString() ?? "anon",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 60,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
            });
    });

    options.AddPolicy("public", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            httpContext.Connection.RemoteIpAddress?.ToString() ?? "anon",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 120,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
            }));
});

var app = builder.Build();

// Forwarded headers are only trusted when the deployment explicitly names its reverse
// proxy. With an empty KnownProxies/KnownNetworks set ASP.NET Core would accept
// X-Forwarded-For from anyone, letting a client mint unlimited rate-limit partitions by
// rotating a fake header. When nothing is configured (local dev) we skip the middleware
// entirely so RemoteIpAddress always reflects the real socket peer.
var knownProxies = builder.Configuration.GetSection("ForwardedHeaders:KnownProxies").Get<string[]>() ?? [];
var knownNetworks = builder.Configuration.GetSection("ForwardedHeaders:KnownNetworks").Get<string[]>() ?? [];
if (knownProxies.Length > 0 || knownNetworks.Length > 0)
{
    var forwardedOptions = new ForwardedHeadersOptions
    {
        ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto,
        ForwardLimit = builder.Configuration.GetValue<int?>("ForwardedHeaders:ForwardLimit") ?? 1,
    };
    forwardedOptions.KnownProxies.Clear();
    forwardedOptions.KnownIPNetworks.Clear();

    foreach (var proxy in knownProxies)
    {
        if (IPAddress.TryParse(proxy, out var address))
            forwardedOptions.KnownProxies.Add(address);
        else
            app.Logger.LogWarning("Ignoring unparseable ForwardedHeaders:KnownProxies entry '{Proxy}'.", proxy);
    }

    foreach (var network in knownNetworks)
    {
        var parts = network.Split('/', 2);
        if (parts.Length == 2
            && IPAddress.TryParse(parts[0], out var prefix)
            && int.TryParse(parts[1], out var prefixLength))
        {
            forwardedOptions.KnownIPNetworks.Add(new System.Net.IPNetwork(prefix, prefixLength));
        }
        else
        {
            app.Logger.LogWarning("Ignoring unparseable ForwardedHeaders:KnownNetworks entry '{Network}'.", network);
        }
    }

    app.UseForwardedHeaders(forwardedOptions);
}

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler();
    app.UseHsts();
    app.UseHttpsRedirection();
}

if (!app.Environment.IsProduction())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

if (useInMemory)
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AumbryeDbContext>();
    db.Database.EnsureCreated();
}
else
{
    app.Services.ApplyDatabaseSchema();
}

app.UseMiddleware<VersionHeaderMiddleware>();
app.UseCors("web");
// Authentication MUST run before the rate limiter: the "runs" and "saves" policies
// partition on ClaimTypes.NameIdentifier, which is only populated once the JWT has been
// validated. Endpoint-scoped RequireRateLimiting policies execute inside the rate-limiter
// middleware, so this ordering keeps per-account partitioning real instead of collapsing
// every authenticated caller into the per-IP fallback.
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

app.MapGet("/api/v1/health", () => Results.Ok(new HealthResponse("ok")))
    .WithTags("Health")
    .WithName("Health")
    .Produces<HealthResponse>(StatusCodes.Status200OK);

app.MapHealthChecks("/api/v1/health/ready", new Microsoft.AspNetCore.Diagnostics.HealthChecks.HealthCheckOptions
{
    ResponseWriter = async (context, report) =>
    {
        context.Response.ContentType = "application/json";
        var checks = report.Entries.Select(e => new
        {
            name = e.Key,
            status = e.Value.Status.ToString(),
            description = e.Value.Description,
        });
        await context.Response.WriteAsJsonAsync(new
        {
            status = report.Status.ToString(),
            checks,
        });
    },
})
.WithTags("Health")
.WithName("HealthReady");

app.MapAuthEndpoints();
app.MapRunsEndpoints();
app.MapSavesEndpoints();
app.MapAccountEndpoints();
app.MapLeaderboardsEndpoints();
app.MapTelemetryEndpoints();

if (app.Environment.IsEnvironment("Testing"))
{
    app.MapGet("/api/v1/__test/throw", (HttpContext _) => throw new InvalidOperationException("test throw"))
        .ExcludeFromDescription();
}

app.Run();

public partial class Program;
