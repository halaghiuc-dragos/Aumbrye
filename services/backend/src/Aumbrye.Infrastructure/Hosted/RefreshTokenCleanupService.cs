using Aumbrye.Domain.Entities;
using Aumbrye.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Aumbrye.Infrastructure.Hosted;

public sealed class RefreshTokenCleanupService : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromHours(1);
    private static readonly TimeSpan Retention = TimeSpan.FromDays(7);
    private readonly IServiceProvider _services;
    private readonly ILogger<RefreshTokenCleanupService> _logger;

    public RefreshTokenCleanupService(
        IServiceProvider services,
        ILogger<RefreshTokenCleanupService> logger)
    {
        _services = services;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CleanupAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Refresh token cleanup failed.");
            }

            await Task.Delay(Interval, stoppingToken);
        }
    }

    private async Task CleanupAsync(CancellationToken ct)
    {
        using var scope = _services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AumbryeDbContext>();
        var cutoff = DateTimeOffset.UtcNow - Retention;

        // A single set-based DELETE. Materializing every expired row to call RemoveRange put
        // hundreds of thousands of entities on the heap per pass once token rotation had been
        // running for a while — token rotation writes a new row on every refresh.
        var deleted = await db.RefreshTokens
            .Where(t => t.ExpiresAt < cutoff)
            .ExecuteDeleteAsync(ct);

        // Revoked-but-unexpired rows are dead weight too: rotation revokes the old token on every
        // refresh, and without this they linger for the full 30-day expiry window.
        deleted += await db.RefreshTokens
            .Where(t => t.RevokedAt != null && t.RevokedAt < cutoff)
            .ExecuteDeleteAsync(ct);

        if (deleted > 0)
            _logger.LogInformation("Deleted {Count} expired or revoked refresh tokens.", deleted);
    }
}
