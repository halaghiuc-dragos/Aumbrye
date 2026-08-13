using Aumbrye.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Aumbrye.IntegrationTests.TestDoubles;

/// <summary>
/// Moves a run's <c>CreatedAt</c> into the past.
/// </summary>
/// <remarks>
/// Completion rejects a client-reported elapsed time that exceeds the server's wall-clock window,
/// so a test that creates a run and immediately claims a two-minute time is correctly refused as
/// implausible. Backdating the row reproduces a run that genuinely took that long, instead of
/// loosening the anti-cheat bound to accommodate synthetic timing.
/// </remarks>
public static class RunClockHelper
{
    public static async Task BackdateAsync(IServiceProvider services, Guid runId, TimeSpan age)
    {
        using var scope = services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AumbryeDbContext>();
        var run = await db.Runs.FirstAsync(r => r.Id == runId);
        run.CreatedAt = DateTimeOffset.UtcNow - age;
        await db.SaveChangesAsync();
    }
}
