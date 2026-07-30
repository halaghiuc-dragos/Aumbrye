using System.Text;
using System.Threading.RateLimiting;
using Aumbrye.Api.Auth;
using Aumbrye.Api.Middleware;
using Aumbrye.Infrastructure;
using Aumbrye.Infrastructure.Persistence;
using Aumbrye.Shared.Contracts;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

var useInMemory = builder.Configuration.GetValue<bool>("UseInMemoryStores")
                  || builder.Environment.IsEnvironment("Testing");

var jwtSecret = builder.Configuration["Jwt:Secret"] ?? "dev-only-change-me-in-production-32chars!!";
if (!useInMemory && builder.Environment.IsProduction()
    && (string.IsNullOrWhiteSpace(jwtSecret) || jwtSecret.Contains("dev-only", StringComparison.Ordinal)))
{
    throw new InvalidOperationException(
        "Jwt:Secret must be set to a strong value in production (appsettings or environment).");
}

builder.Services.AddInfrastructure(builder.Configuration, useInMemory);

var key = Encoding.UTF8.GetBytes(jwtSecret.PadRight(32)[..32]);

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
            IssuerSigningKey = new SymmetricSecurityKey(key),
            ClockSkew = TimeSpan.FromMinutes(1),
        };
    });
builder.Services.AddAuthorization();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddFixedWindowLimiter("auth", limiter =>
    {
        limiter.PermitLimit = 30;
        limiter.Window = TimeSpan.FromMinutes(1);
        limiter.QueueLimit = 0;
    });
});

var app = builder.Build();

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
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/api/v1/health", () => Results.Ok(new HealthResponse("ok")));
app.MapAuthEndpoints();
app.MapRunsEndpoints();

app.Run();

public partial class Program;
