using Aumbrye.Application.Services;
using Xunit;

namespace Aumbrye.UnitTests;

public class LeaderboardServiceTests
{
    [Fact]
    public async Task InMemoryStore_SubmitAndQuery_ReturnsOrderedEntries()
    {
        var store = new InMemoryLeaderboardStore();
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        var now = DateTimeOffset.UtcNow;
        await store.SubmitScoreAsync(a, "player-a", "frozen_fortress", 1, 120.5, now);
        await store.SubmitScoreAsync(b, "player-b", "frozen_fortress", 1, 95.0, now);
        var top = await store.GetTopAsync("frozen_fortress", 1, 10);
        Assert.Equal(2, top.Count);
        Assert.Equal(b, top[0].AccountId);
        Assert.Equal(95.0, top[0].ElapsedSeconds);
    }

    [Fact]
    public async Task InMemoryStore_FiltersByBiomeAndTier()
    {
        var store = new InMemoryLeaderboardStore();
        var id = Guid.NewGuid();
        var now = DateTimeOffset.UtcNow;
        await store.SubmitScoreAsync(id, "player", "dark_cathedral", 2, 200.0, now);
        var wrongBiome = await store.GetTopAsync("forgotten_castle", 2, 10);
        var wrongTier = await store.GetTopAsync("dark_cathedral", 1, 10);
        Assert.Empty(wrongBiome);
        Assert.Empty(wrongTier);
    }
}
