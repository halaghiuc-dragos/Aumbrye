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
        var expired = await db.RefreshTokens
            .Where(t => t.ExpiresAt < cutoff)
            .ToListAsync(ct);
        if (expired.Count == 0)
            return;

        db.RefreshTokens.RemoveRange(expired);
        await db.SaveChangesAsync(ct);
        _logger.LogInformation("Deleted {Count} expired refresh tokens.", expired.Count);
    }
}
