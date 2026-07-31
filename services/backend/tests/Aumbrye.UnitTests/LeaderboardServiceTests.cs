using Aumbrye.Application.Services;
using Xunit;

namespace Aumbrye.UnitTests;

public class LeaderboardServiceTests
{
    [Fact]
    public async Task InMemory_SubmitAndQuery_ReturnsOrderedEntries()
    {
        var svc = new InMemoryLeaderboardService();
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        await svc.SubmitScoreAsync(a, "frozen_fortress", 1, 120.5);
        await svc.SubmitScoreAsync(b, "frozen_fortress", 1, 95.0);
        var top = await svc.GetTopAsync("frozen_fortress", 1, 10);
        Assert.Equal(2, top.Count);
        Assert.Equal(b, top[0].AccountId);
        Assert.Equal(95.0, top[0].ElapsedSeconds);
    }

    [Fact]
    public async Task InMemory_FiltersByBiomeAndTier()
    {
        var svc = new InMemoryLeaderboardService();
        var id = Guid.NewGuid();
        await svc.SubmitScoreAsync(id, "dark_cathedral", 2, 200.0);
        var wrongBiome = await svc.GetTopAsync("forgotten_castle", 2, 10);
        var wrongTier = await svc.GetTopAsync("dark_cathedral", 1, 10);
        Assert.Empty(wrongBiome);
        Assert.Empty(wrongTier);
    }
}
