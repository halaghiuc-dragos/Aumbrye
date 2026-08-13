using System.Text.Json;
using Aumbrye.Application.Services;
using StackExchange.Redis;

namespace Aumbrye.Infrastructure.Caching;

/// <summary>
/// Redis-backed leaderboards.
/// </summary>
/// <remarks>
/// Layout per board:
/// <list type="bullet">
/// <item><c>leaderboard:{biome}:tier{t}</c> — sorted set, member = account id, score = elapsed seconds.</item>
/// <item><c>leaderboard:{biome}:tier{t}:meta</c> — hash, field = account id, value = {displayName, submittedAt}.</item>
/// </list>
/// Plus a per-account index <c>leaderboard:account:{id}:boards</c> (a set of <c>biome|tier</c>
/// pairs) so export and erasure are direct key lookups instead of a SCAN over the keyspace.
/// </remarks>
public class RedisLeaderboardStore : ILeaderboardStore
{
    private const int MaxEntriesPerKey = 1000;
    private readonly IConnectionMultiplexer _redis;

    public RedisLeaderboardStore(IConnectionMultiplexer redis) => _redis = redis;

    private static string Key(string biomeId, int tier) => $"leaderboard:{biomeId}:tier{tier}";

    private static string MetaKey(string biomeId, int tier) => $"leaderboard:{biomeId}:tier{tier}:meta";

    private static string AccountIndexKey(Guid accountId) => $"leaderboard:account:{accountId:N}:boards";

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
        var member = LeaderboardMemberFormat.Format(accountId);

        // SortedSetWhen.LessThan (Redis 6.2 ZADD LT) keeps the player's personal best: a slower
        // resubmission is ignored rather than overwriting a faster time.
        var improved = await db.SortedSetAddAsync(
            redisKey, member, elapsedSeconds, SortedSetWhen.LessThan);

        // The metadata hash always refreshes so a renamed player is displayed correctly, but the
        // submission instant only advances when the score itself improved.
        var existingMeta = improved ? RedisValue.Null : await db.HashGetAsync(MetaKey(biomeId, tier), member);
        var metaSubmittedAt = submittedAt;
        if (!improved && existingMeta.HasValue && TryReadMeta(existingMeta!, out _, out var previousAt))
            metaSubmittedAt = previousAt;

        await db.HashSetAsync(MetaKey(biomeId, tier), member, SerializeMeta(displayName, metaSubmittedAt));
        await db.SetAddAsync(AccountIndexKey(accountId), $"{biomeId}|{tier}");

        await TrimAsync(db, biomeId, tier);

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
        if (values.Length == 0)
            return [];

        var metaValues = await db.HashGetAsync(
            MetaKey(biomeId, tier),
            values.Select(v => (RedisValue)v.Element.ToString()).ToArray());

        var entries = new List<LeaderboardEntry>(values.Length);
        for (var i = 0; i < values.Length; i++)
        {
            var rawMember = values[i].Element.ToString();
            if (!LeaderboardMemberFormat.TryParse(rawMember, out var accountId))
                continue;

            var displayName = LeaderboardMemberFormat.LegacyDisplayName(rawMember);
            var submittedAt = LeaderboardMemberFormat.LegacySubmittedAt(rawMember) ?? DateTimeOffset.UnixEpoch;
            if (i < metaValues.Length
                && metaValues[i].HasValue
                && TryReadMeta(metaValues[i]!, out var metaName, out var metaAt))
            {
                displayName = metaName;
                submittedAt = metaAt;
            }

            entries.Add(new LeaderboardEntry(
                accountId,
                displayName ?? accountId.ToString()[..8],
                biomeId,
                tier,
                values[i].Score,
                submittedAt));
        }
        return entries;
    }

    public async Task<IReadOnlyList<LeaderboardEntry>> GetEntriesForAccountAsync(
        Guid accountId,
        CancellationToken ct = default)
    {
        var db = _redis.GetDatabase();
        var member = LeaderboardMemberFormat.Format(accountId);
        var entries = new List<LeaderboardEntry>();

        foreach (var (biomeId, tier) in await ReadAccountBoardsAsync(db, accountId))
        {
            var score = await db.SortedSetScoreAsync(Key(biomeId, tier), member);
            if (!score.HasValue)
                continue;

            var displayName = accountId.ToString()[..8];
            var submittedAt = DateTimeOffset.UnixEpoch;
            var meta = await db.HashGetAsync(MetaKey(biomeId, tier), member);
            if (meta.HasValue && TryReadMeta(meta!, out var metaName, out var metaAt))
            {
                displayName = metaName ?? displayName;
                submittedAt = metaAt;
            }

            entries.Add(new LeaderboardEntry(
                accountId, displayName, biomeId, tier, score.Value, submittedAt));
        }

        return entries;
    }

    public async Task RemoveAccountAsync(Guid accountId, CancellationToken ct = default)
    {
        var db = _redis.GetDatabase();
        var member = LeaderboardMemberFormat.Format(accountId);

        foreach (var (biomeId, tier) in await ReadAccountBoardsAsync(db, accountId))
        {
            await db.SortedSetRemoveAsync(Key(biomeId, tier), member);
            await db.HashDeleteAsync(MetaKey(biomeId, tier), member);
        }

        await db.KeyDeleteAsync(AccountIndexKey(accountId));
    }

    private static async Task<List<(string BiomeId, int Tier)>> ReadAccountBoardsAsync(IDatabase db, Guid accountId)
    {
        var boards = new List<(string, int)>();
        foreach (var raw in await db.SetMembersAsync(AccountIndexKey(accountId)))
        {
            var parts = raw.ToString().Split('|', 2);
            if (parts.Length == 2 && int.TryParse(parts[1], out var tier))
                boards.Add((parts[0], tier));
        }
        return boards;
    }

    /// <summary>
    /// Drops everything past <see cref="MaxEntriesPerKey"/>. Scores are elapsed seconds sorted
    /// ascending, so rank 0 is the fastest run on the board — the tail is what must go.
    /// </summary>
    private static async Task TrimAsync(IDatabase db, string biomeId, int tier)
    {
        var redisKey = Key(biomeId, tier);
        var evicted = await db.SortedSetRangeByRankAsync(redisKey, MaxEntriesPerKey, -1);
        if (evicted.Length == 0)
            return;

        await db.SortedSetRemoveRangeByRankAsync(redisKey, MaxEntriesPerKey, -1);
        await db.HashDeleteAsync(MetaKey(biomeId, tier), evicted);
    }

    private static string SerializeMeta(string displayName, DateTimeOffset submittedAt) =>
        JsonSerializer.Serialize(new LeaderboardEntryMeta(displayName, submittedAt.ToUnixTimeSeconds()));

    private static bool TryReadMeta(string raw, out string? displayName, out DateTimeOffset submittedAt)
    {
        displayName = null;
        submittedAt = DateTimeOffset.UnixEpoch;
        try
        {
            var meta = JsonSerializer.Deserialize<LeaderboardEntryMeta>(raw);
            if (meta == null)
                return false;
            displayName = meta.DisplayName;
            submittedAt = DateTimeOffset.FromUnixTimeSeconds(meta.SubmittedAtUnix);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private sealed record LeaderboardEntryMeta(string DisplayName, long SubmittedAtUnix);
}
