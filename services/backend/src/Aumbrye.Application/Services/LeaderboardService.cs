using Aumbrye.Application.Abstractions;

namespace Aumbrye.Application.Services;

public interface ILeaderboardService
{
    Task SubmitScoreAsync(Guid accountId, string biomeId, int tier, double elapsedSeconds, CancellationToken ct = default);
    Task<IReadOnlyList<LeaderboardEntry>> GetTopAsync(string biomeId, int tier, int limit = 10, CancellationToken ct = default);
}

public sealed record LeaderboardEntry(
    Guid AccountId,
    string DisplayName,
    string BiomeId,
    int Tier,
    double ElapsedSeconds,
    DateTimeOffset SubmittedAt);

public class InMemoryLeaderboardService : ILeaderboardService
{
    private static readonly object Gate = new();
    private static readonly List<LeaderboardEntry> Entries = [];

    public Task SubmitScoreAsync(Guid accountId, string biomeId, int tier, double elapsedSeconds, CancellationToken ct = default)
    {
        lock (Gate)
        {
            Entries.Add(new LeaderboardEntry(
                accountId,
                accountId.ToString()[..8],
                biomeId,
                tier,
                elapsedSeconds,
                DateTimeOffset.UtcNow));
        }
        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<LeaderboardEntry>> GetTopAsync(string biomeId, int tier, int limit = 10, CancellationToken ct = default)
    {
        lock (Gate)
        {
            var top = Entries
                .Where(e => e.BiomeId == biomeId && e.Tier == tier)
                .OrderBy(e => e.ElapsedSeconds)
                .Take(limit)
                .ToList();
            return Task.FromResult<IReadOnlyList<LeaderboardEntry>>(top);
        }
    }
}
