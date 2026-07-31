using Aumbrye.Application.Services;
using StackExchange.Redis;

namespace Aumbrye.Infrastructure.Caching;

public class RedisLeaderboardService : ILeaderboardService
{
    private readonly IConnectionMultiplexer _redis;

    public RedisLeaderboardService(IConnectionMultiplexer redis) => _redis = redis;

    private static string Key(string biomeId, int tier) => $"leaderboard:{biomeId}:tier{tier}";

    public async Task SubmitScoreAsync(Guid accountId, string biomeId, int tier, double elapsedSeconds, CancellationToken ct = default)
    {
        var db = _redis.GetDatabase();
        var member = $"{accountId:N}|{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}";
        await db.SortedSetAddAsync(Key(biomeId, tier), member, elapsedSeconds);
    }

    public async Task<IReadOnlyList<LeaderboardEntry>> GetTopAsync(string biomeId, int tier, int limit = 10, CancellationToken ct = default)
    {
        var db = _redis.GetDatabase();
        var values = await db.SortedSetRangeByRankWithScoresAsync(Key(biomeId, tier), 0, limit - 1);
        var entries = new List<LeaderboardEntry>();
        foreach (var entry in values)
        {
            var parts = entry.Element.ToString().Split('|');
            if (!Guid.TryParse(parts[0], out var accountId))
                continue;
            entries.Add(new LeaderboardEntry(
                accountId,
                accountId.ToString()[..8],
                biomeId,
                tier,
                entry.Score,
                DateTimeOffset.UtcNow));
        }
        return entries;
    }
}
