using Aumbrye.Application.Abstractions;
using Aumbrye.Procedural.Generation;

namespace Aumbrye.IntegrationTests.TestDoubles;

public sealed class CountingDungeonGenerator : IDungeonGenerator
{
    public int GenerateCallCount { get; private set; }

    public void Reset() => GenerateCallCount = 0;

    public (string Json, string? Checksum) Generate(
        string biomeId,
        int seed,
        int tier,
        int playerLevel,
        Guid runId)
    {
        GenerateCallCount++;
        var result = DungeonGenerator.Generate(biomeId, seed, tier, playerLevel, runId);
        return (result.Json, result.Definition.Checksum);
    }
}
