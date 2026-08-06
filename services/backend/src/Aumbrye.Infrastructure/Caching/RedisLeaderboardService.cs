using Aumbrye.Application.Services;
using StackExchange.Redis;

namespace Aumbrye.Infrastructure.Caching;

public class RedisLeaderboardStore : ILeaderboardStore
{
    private const int MaxEntriesPerKey = 1000;
    private readonly IConnectionMultiplexer _redis;

    public RedisLeaderboardStore(IConnectionMultiplexer redis) => _redis = redis;

    private static string Key(string biomeId, int tier) => $"leaderboard:{biomeId}:tier{tier}";

    public async Task<int> SubmitScoreAsync(
        Guid accountId,
        string displayName,
        string biomeId,
        int tier,
        double elapsedSeconds,
        DateTimeOffset submittedAt,
        CancellationToken ct = default)
    {
        var db = _redis.GetDatabase();
        var redisKey = Key(biomeId, tier);
        var member = LeaderboardMemberFormat.Format(accountId, submittedAt, displayName);
        await db.SortedSetAddAsync(redisKey, member, elapsedSeconds);
        await TrimAsync(db, redisKey);
        var rank = await db.SortedSetRankAsync(redisKey, member, Order.Ascending);
        return rank.HasValue ? (int)rank.Value + 1 : 1;
    }

    public async Task<IReadOnlyList<LeaderboardEntry>> GetTopAsync(
        string biomeId,
        int tier,
        int limit,
        CancellationToken ct = default)
    {
        var db = _redis.GetDatabase();
        var values = await db.SortedSetRangeByRankWithScoresAsync(Key(biomeId, tier), 0, limit - 1);
        var entries = new List<LeaderboardEntry>();
        foreach (var entry in values)
        {
            if (!LeaderboardMemberFormat.TryParse(entry.Element.ToString(), out var accountId, out var submittedAt, out var displayName))
                continue;
            entries.Add(new LeaderboardEntry(
                accountId,
                displayName,
                biomeId,
                tier,
                entry.Score,
                submittedAt));
        }
        return entries;
    }

    private static async Task TrimAsync(IDatabase db, RedisKey redisKey)
    {
        var count = await db.SortedSetLengthAsync(redisKey);
        if (count <= MaxEntriesPerKey)
            return;
        await db.SortedSetRemoveRangeByRankAsync(redisKey, 0, (int)count - MaxEntriesPerKey - 1);
    }
}
