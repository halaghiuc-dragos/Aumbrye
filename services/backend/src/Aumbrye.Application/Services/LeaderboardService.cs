using Aumbrye.Application.Abstractions;
using Aumbrye.Application.Services;
using Aumbrye.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Aumbrye.Application.Services;

public interface ILeaderboardStore
{
    Task<int> SubmitScoreAsync(
        Guid accountId,
        string displayName,
        string biomeId,
        int tier,
        double elapsedSeconds,
        DateTimeOffset submittedAt,
        CancellationToken ct = default);

    Task<IReadOnlyList<LeaderboardEntry>> GetTopAsync(
        string biomeId,
        int tier,
        int limit,
        CancellationToken ct = default);
}

public sealed record LeaderboardEntry(
    Guid AccountId,
    string DisplayName,
    string BiomeId,
    int Tier,
    double ElapsedSeconds,
    DateTimeOffset SubmittedAt);

public sealed record LeaderboardSubmitResult(
    bool Submitted,
    int? Rank = null,
    string? Reason = null,
    string? Error = null,
    int? StatusCode = null);

public interface ILeaderboardService
{
    Task<LeaderboardSubmitResult> SubmitFromRunAsync(
        Guid accountId,
        Guid runId,
        bool optIn,
        CancellationToken ct = default);

    Task<IReadOnlyList<LeaderboardEntry>> GetTopAsync(
        string biomeId,
        int tier,
        int limit = 10,
        CancellationToken ct = default);
}

public class LeaderboardService : ILeaderboardService
{
    private const int MaxLimit = 100;
    private readonly DbContext _db;
    private readonly ILeaderboardStore _store;

    public LeaderboardService(DbContext db, ILeaderboardStore store)
    {
        _db = db;
        _store = store;
    }

    public async Task<LeaderboardSubmitResult> SubmitFromRunAsync(
        Guid accountId,
        Guid runId,
        bool optIn,
        CancellationToken ct = default)
    {
        if (!optIn)
            return new LeaderboardSubmitResult(false, Reason: "opt_out");

        var run = await _db.Set<Run>().FirstOrDefaultAsync(r => r.Id == runId, ct);
        if (run == null)
            return new LeaderboardSubmitResult(false, Error: "Run not found.", StatusCode: 404);
        if (run.AccountId != accountId)
            return new LeaderboardSubmitResult(false, Error: "Run belongs to another account.", StatusCode: 403);
        if (run.Status != RunStatus.Completed || run.CompletedAt == null)
            return new LeaderboardSubmitResult(false, Error: "Run is not completed.", StatusCode: 400);

        var account = await _db.Set<Account>().FirstOrDefaultAsync(a => a.Id == accountId, ct);
        if (account == null)
            return new LeaderboardSubmitResult(false, Error: "Account not found.", StatusCode: 404);

        var elapsed = (run.CompletedAt.Value - run.CreatedAt).TotalSeconds;
        var submittedAt = DateTimeOffset.UtcNow;
        var rank = await _store.SubmitScoreAsync(
            accountId,
            account.DisplayName,
            run.BiomeId,
            run.Tier,
            elapsed,
            submittedAt,
            ct);
        return new LeaderboardSubmitResult(true, Rank: rank);
    }

    public Task<IReadOnlyList<LeaderboardEntry>> GetTopAsync(
        string biomeId,
        int tier,
        int limit = 10,
        CancellationToken ct = default) =>
        _store.GetTopAsync(biomeId, tier, Math.Clamp(limit, 1, MaxLimit), ct);
}

public class InMemoryLeaderboardStore : ILeaderboardStore
{
    private const int MaxEntriesPerKey = 1000;
    private readonly object _gate = new();
    private readonly Dictionary<string, List<LeaderboardEntry>> _entries = new(StringComparer.Ordinal);

    private static string Key(string biomeId, int tier) => $"{biomeId}:{tier}";

    public Task<int> SubmitScoreAsync(
        Guid accountId,
        string displayName,
        string biomeId,
        int tier,
        double elapsedSeconds,
        DateTimeOffset submittedAt,
        CancellationToken ct = default)
    {
        lock (_gate)
        {
            var key = Key(biomeId, tier);
            if (!_entries.TryGetValue(key, out var list))
            {
                list = [];
                _entries[key] = list;
            }

            list.Add(new LeaderboardEntry(accountId, displayName, biomeId, tier, elapsedSeconds, submittedAt));
            if (list.Count > MaxEntriesPerKey)
                list.RemoveRange(0, list.Count - MaxEntriesPerKey);

            var rank = list
                .OrderBy(e => e.ElapsedSeconds)
                .Select((e, i) => new { e.AccountId, Rank = i + 1 })
                .First(x => x.AccountId == accountId)
                .Rank;
            return Task.FromResult(rank);
        }
    }

    public Task<IReadOnlyList<LeaderboardEntry>> GetTopAsync(
        string biomeId,
        int tier,
        int limit,
        CancellationToken ct = default)
    {
        lock (_gate)
        {
            if (!_entries.TryGetValue(Key(biomeId, tier), out var list))
                return Task.FromResult<IReadOnlyList<LeaderboardEntry>>([]);

            var top = list
                .OrderBy(e => e.ElapsedSeconds)
                .Take(limit)
                .ToList();
            return Task.FromResult<IReadOnlyList<LeaderboardEntry>>(top);
        }
    }
}
