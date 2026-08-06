using System.Diagnostics.Metrics;

namespace Aumbrye.Application.Services;

public static class ApiMetrics
{
    private static readonly Meter Meter = new("Aumbrye.Api");

    public static readonly Counter<long> RunsCreated =
        Meter.CreateCounter<long>("runs.created");

    public static readonly Counter<long> RunsCompleted =
        Meter.CreateCounter<long>("runs.completed");

    public static readonly Counter<long> LootClaimsRejected =
        Meter.CreateCounter<long>("loot.claims.rejected");
}
