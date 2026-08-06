using Aumbrye.Procedural;
using Aumbrye.Procedural.Generation;
using Aumbrye.Procedural.Models;
using Aumbrye.Procedural.Serialization;
using Aumbrye.Shared.Contracts;
using Xunit;

namespace Aumbrye.UnitTests;

public class ProceduralAssemblyTests
{
    [Fact]
    public void Version_MatchesApiExpectedClientVersion()
    {
        Assert.Equal(ApiVersions.ExpectedClientVersion, ProceduralAssembly.Version);
    }

    [Fact]
    public void Version_MatchesGodotApiConfigClientVersion()
    {
        var repoRoot = FindRepoRoot();
        var apiConfigPath = Path.Combine(
            repoRoot,
            "apps",
            "game",
            "client",
            "scripts",
            "net",
            "api_config.gd");
        Assert.True(File.Exists(apiConfigPath), $"Missing {apiConfigPath}");
        var text = File.ReadAllText(apiConfigPath);
        const string marker = "const CLIENT_VERSION := \"";
        var start = text.IndexOf(marker, StringComparison.Ordinal);
        Assert.True(start >= 0, "CLIENT_VERSION constant not found in api_config.gd");
        start += marker.Length;
        var end = text.IndexOf('"', start);
        var godotVersion = text[start..end];
        Assert.Equal(godotVersion, ProceduralAssembly.Version);
    }

    private static string FindRepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, "apps", "game", "client")))
                return dir.FullName;
            dir = dir.Parent;
        }

        throw new InvalidOperationException("Could not locate repository root.");
    }
}

public class CanonicalJsonSerializerTests
{
    [Fact]
    public void Serialize_ReturnsChecksumMatchingRecomputedHash()
    {
        var definition = BuildSampleDefinition();
        var (json, checksum) = CanonicalJsonSerializer.Serialize(definition);
        Assert.Matches("^[a-f0-9]{64}$", checksum);
        Assert.Contains($"\"checksum\":\"{checksum}\"", json);

        var prefix = json[..json.IndexOf(",\"checksum\":\"", StringComparison.Ordinal)];
        var suffixStart = json.IndexOf('"', json.IndexOf(",\"checksum\":\"", StringComparison.Ordinal) + 14) + 1;
        var suffix = json[suffixStart..];
        var jsonWithoutChecksum = prefix + suffix;
        var recomputed = CanonicalJsonSerializer.ComputeChecksum(jsonWithoutChecksum);
        Assert.Equal(checksum, recomputed);
    }

    [Fact]
    public void Serialize_IsByteIdenticalForSameDefinition()
    {
        var definition = BuildSampleDefinition();
        var first = CanonicalJsonSerializer.Serialize(definition);
        var second = CanonicalJsonSerializer.Serialize(definition);
        Assert.Equal(first.Json, second.Json);
        Assert.Equal(first.Checksum, second.Checksum);
    }

    [Fact]
    public void Serialize_SortsKeysOrdinally()
    {
        var definition = BuildSampleDefinition();
        var (json, _) = CanonicalJsonSerializer.Serialize(definition);
        Assert.StartsWith("{\"biomeId\":", json, StringComparison.Ordinal);
        var checksumIndex = json.IndexOf("\"checksum\":", StringComparison.Ordinal);
        var schemaIndex = json.IndexOf("\"schemaVersion\":", StringComparison.Ordinal);
        Assert.True(schemaIndex > checksumIndex);
    }

    private static DungeonDefinition BuildSampleDefinition()
    {
        var runId = Guid.Parse("00000000-0000-4000-8000-000000000099");
        return new DungeonDefinition(
            SchemaVersion: 1,
            RunId: runId,
            Seed: 42,
            BiomeId: "forgotten_castle",
            Tier: 1,
            PlayerLevelSnapshot: 1,
            Rooms:
            [
                new DungeonRoom("entrance", "fc_entrance", "hub", new DungeonTransform(0, 0, 0, 0), ["spawn"]),
            ],
            Edges: [],
            Placements: new DungeonPlacements([], [], [], [], [], null, null, "entrance"),
            Budgets: new DungeonBudgets(0, 0),
            RoomContent: Array.Empty<RoomContentEntry>(),
            Locks: Array.Empty<DungeonLock>(),
            Puzzles: Array.Empty<DungeonPuzzle>());
    }
}
