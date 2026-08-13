using Aumbrye.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Aumbrye.Application.Services;

public interface ILeaderboardStore
{
    /// <summary>
    /// Records a player's time on a board, keeping only their best. Returns the account's rank
    /// (1-based) on that board after the write. Implementations must hold at most one entry per
    /// account per board and must not downgrade an existing better time.
    /// </summary>
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

    /// <summary>Every board row belonging to an account, for GDPR export.</summary>
    Task<IReadOnlyList<LeaderboardEntry>> GetEntriesForAccountAsync(
        Guid accountId,
        CancellationToken ct = default);

    /// <summary>Erases every board row belonging to an account, for GDPR erasure.</summary>
    Task RemoveAccountAsync(Guid accountId, CancellationToken ct = default);
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

        // Rank by the validated client-reported time when we have one. That clock excludes pause
        // and menu time (matching what speedrunners actually compete on) and CompleteRunAsync has
        // already bounded it against the server's wall clock. The wall-clock window is only the
        // fallback for runs completed before ElapsedSeconds was persisted.
        var elapsed = run.ElapsedSeconds ?? (run.CompletedAt.Value - run.CreatedAt).TotalSeconds;

        // A completed run contributes exactly one submission. Replays of the same run (the client
        // retries POSTs, and the cloud outbox re-sends on the next boot) return the original rank
        // rather than re-submitting.
        if (run.LeaderboardSubmittedAt != null)
        {
            var rank = await RankOfAsync(accountId, run.BiomeId, run.Tier, ct);
            return new LeaderboardSubmitResult(true, Rank: rank, Reason: "already_submitted");
        }

        var submittedAt = DateTimeOffset.UtcNow;
        var newRank = await _store.SubmitScoreAsync(
            accountId,
            account.DisplayName,
            run.BiomeId,
            run.Tier,
            elapsed,
            submittedAt,
            ct);

        run.LeaderboardSubmittedAt = submittedAt;
        await _db.SaveChangesAsync(ct);

        return new LeaderboardSubmitResult(true, Rank: newRank);
    }

    public Task<IReadOnlyList<LeaderboardEntry>> GetTopAsync(
        string biomeId,
        int tier,
        int limit = 10,
        CancellationToken ct = default) =>
        _store.GetTopAsync(biomeId, tier, Math.Clamp(limit, 1, MaxLimit), ct);

    private async Task<int?> RankOfAsync(Guid accountId, string biomeId, int tier, CancellationToken ct)
    {
        var top = await _store.GetTopAsync(biomeId, tier, MaxLimit, ct);
        for (var i = 0; i < top.Count; i++)
        {
            if (top[i].AccountId == accountId)
                return i + 1;
        }
        return null;
    }
}

public class InMemoryLeaderboardStore : ILeaderboardStore
{
    private const int MaxEntriesPerKey = 1000;
    private readonly object _gate = new();

    // One entry per account per board, mirroring the Redis sorted-set-with-unique-members rule.
    private readonly Dictionary<string, Dictionary<Guid, LeaderboardEntry>> _entries =
        new(StringComparer.Ordinal);

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
            if (!_entries.TryGetValue(key, out var board))
            {
                board = [];
                _entries[key] = board;
            }

            // Keep the player's best time; a slower run never demotes an existing entry.
            if (!board.TryGetValue(accountId, out var current) || elapsedSeconds < current.ElapsedSeconds)
            {
                board[accountId] = new LeaderboardEntry(
                    accountId, displayName, biomeId, tier, elapsedSeconds, submittedAt);
            }
            else
            {
                // Refresh the display name even when the time does not improve.
                board[accountId] = current with { DisplayName = displayName };
            }

            if (board.Count > MaxEntriesPerKey)
            {
                // Evict the SLOWEST entries — the fast end of the board is the part worth keeping.
                foreach (var slow in board.Values
                             .OrderByDescending(e => e.ElapsedSeconds)
                             .Take(board.Count - MaxEntriesPerKey)
                             .Select(e => e.AccountId)
                             .ToList())
                {
                    board.Remove(slow);
                }
            }

            var rank = board.Values
                .OrderBy(e => e.ElapsedSeconds)
                .Select((e, i) => new { e.AccountId, Rank = i + 1 })
                .FirstOrDefault(x => x.AccountId == accountId)?.Rank ?? board.Count;
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
            if (!_entries.TryGetValue(Key(biomeId, tier), out var board))
                return Task.FromResult<IReadOnlyList<LeaderboardEntry>>([]);

            var top = board.Values
                .OrderBy(e => e.ElapsedSeconds)
                .Take(limit)
                .ToList();
            return Task.FromResult<IReadOnlyList<LeaderboardEntry>>(top);
        }
    }

    public Task<IReadOnlyList<LeaderboardEntry>> GetEntriesForAccountAsync(
        Guid accountId,
        CancellationToken ct = default)
    {
        lock (_gate)
        {
            var owned = _entries.Values
                .Where(board => board.ContainsKey(accountId))
                .Select(board => board[accountId])
                .ToList();
            return Task.FromResult<IReadOnlyList<LeaderboardEntry>>(owned);
        }
    }

    public Task RemoveAccountAsync(Guid accountId, CancellationToken ct = default)
    {
        lock (_gate)
        {
            foreach (var board in _entries.Values)
                board.Remove(accountId);
        }
        return Task.CompletedTask;
    }
}
