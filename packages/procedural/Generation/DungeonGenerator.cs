using Aumbrye.Procedural.Assignment;
using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Content;
using Aumbrye.Procedural.Layout;
using Aumbrye.Procedural.Models;
using Aumbrye.Procedural.Placement;
using Aumbrye.Procedural.Random;
using Aumbrye.Procedural.Serialization;
using Aumbrye.Procedural.Validation;

namespace Aumbrye.Procedural.Generation;

public sealed record GenerationResult(DungeonDefinition Definition, string Json);

public sealed class GenerationOptions
{
    public int MaxAttempts { get; init; } = 48;
    public int SeedOffsetPerAttempt { get; init; } = 1_000_003;
}

/// <summary>
/// Main procedural entry — layout through canonical JSON.
/// GDScript DungeonProcgen is authoritative for gameplay; this path exists for backend/CLI parity.
/// </summary>
public static class DungeonGenerator
{
    public static GenerationResult Generate(
        string biomeId,
        int seed,
        int tier,
        int playerLevel,
        Guid runId,
        int floorIndex = 1,
        bool isFinalFloor = false,
        GenerationOptions? options = null)
    {
        options ??= new GenerationOptions();
        var biome = BiomeCatalog.GetRequired(biomeId);
        if (isFinalFloor)
            return FinalFloorGenerator.Generate(biome, seed, tier, playerLevel, runId, floorIndex);

        var effectiveSeed = DungeonSeedDeriver.MixFloorSeed(seed, floorIndex);
        var layoutRules = new BiomeLayoutRules(
            biome.Id,
            biome.RoomCountMin,
            biome.RoomCountMax,
            14);

        Exception? lastError = null;
        for (var attempt = 0; attempt < options.MaxAttempts; attempt++)
        {
            var attemptSeed = effectiveSeed + attempt * options.SeedOffsetPerAttempt;
            try
            {
                var result = TryGenerateOnce(biome, layoutRules, attemptSeed, tier, playerLevel, runId, floorIndex, false);
                return result;
            }
            catch (Exception ex)
            {
                lastError = ex;
            }
        }

        throw new InvalidOperationException(
            $"Failed to generate dungeon for biome '{biomeId}' after {options.MaxAttempts} attempts.",
            lastError);
    }

    public static GenerationResult TryGenerateOnce(
        BiomeDefinition biome,
        BiomeLayoutRules layoutRules,
        int seed,
        int tier,
        int playerLevel,
        Guid runId,
        int floorIndex = 1,
        bool isFinalFloor = false)
    {
        if (isFinalFloor)
            return FinalFloorGenerator.Generate(biome, seed, tier, playerLevel, runId, floorIndex);
        var graph = LayoutGraphGenerator.Generate(layoutRules, seed);
        var rng = new SeededRandom(seed ^ 0x5EED);

        var assignment = RoomTypeAssigner.Assign(biome, graph, rng);
        RoomPlacement.ValidateDoorTopology(graph, assignment);
        var validation = ConnectivityValidator.Validate(
            graph,
            assignment.EntranceLayoutId,
            assignment.BossLayoutId,
            biome.RequiresSecret,
            assignment.SecretLayoutIds);
        if (!validation.IsValid)
            throw new InvalidOperationException(validation.FailureReason);

        var (enemies, threatUsed) = EnemyPlacer.Place(biome, assignment, tier, playerLevel, rng);
        var placements = AssignLootInstanceIds(
            LootPlacer.Place(biome, assignment, enemies, tier, playerLevel, seed, rng),
            runId);

        var rooms = RoomPlacement.BuildRooms(graph, assignment);
        var edges = assignment.Edges
            .Select(e => new DungeonEdge(e.From, e.To, e.Kind))
            .ToList();

        var lootValue = placements.Loot
            .SelectMany(l => l.Items)
            .Sum(i => i.Quantity * ItemCatalog.GetLootValue(i.ItemId));

        var definition = new DungeonDefinition(
            SchemaVersion: 1,
            RunId: runId,
            Seed: seed,
            BiomeId: biome.Id,
            Tier: tier,
            PlayerLevelSnapshot: playerLevel,
            Rooms: rooms,
            Edges: edges,
            Placements: placements,
            Budgets: new DungeonBudgets(threatUsed, lootValue),
            FloorIndex: floorIndex,
            IsFinalFloor: isFinalFloor,
            RoomContent: Array.Empty<RoomContentEntry>(),
            Locks: Array.Empty<DungeonLock>(),
            Puzzles: Array.Empty<DungeonPuzzle>());

        var (json, checksum) = CanonicalJsonSerializer.Serialize(definition);
        return new GenerationResult(definition with { Checksum = checksum }, json);
    }

    private static DungeonPlacements AssignLootInstanceIds(DungeonPlacements placements, Guid runId)
    {
        var loot = placements.Loot
            .Select(chest =>
            {
                var items = chest.Items
                    .Select((item, index) => item with
                    {
                        InstanceId = CreateLootInstanceId(runId, chest.ChestId, item.ItemId, index).ToString(),
                    })
                    .ToList();
                return chest with { Items = items };
            })
            .ToList();
        return placements with { Loot = loot };
    }

    private static Guid CreateLootInstanceId(Guid runId, string chestId, string itemId, int index)
    {
        var name = $"{chestId}:{itemId}:{index}";
        var bytes = System.Text.Encoding.UTF8.GetBytes(name);
        return GuidExtensions.CreateVersion5(runId, bytes);
    }
}

internal static class GuidExtensions
{
    [System.Diagnostics.CodeAnalysis.SuppressMessage(
        "Security",
        "CA5350:Do Not Use Weak Cryptographic Algorithms",
        Justification = "RFC 4122 UUID v5 name hashing requires SHA-1.")]
    public static Guid CreateVersion5(Guid namespaceId, byte[] name)
    {
        var namespaceBytes = namespaceId.ToByteArray();
        SwapByteOrder(namespaceBytes);
        var data = new byte[namespaceBytes.Length + name.Length];
        Buffer.BlockCopy(namespaceBytes, 0, data, 0, namespaceBytes.Length);
        Buffer.BlockCopy(name, 0, data, namespaceBytes.Length, name.Length);
#pragma warning disable CA5350 // SHA-1 required for UUID v5 (RFC 4122)
        var hash = System.Security.Cryptography.SHA1.HashData(data);
#pragma warning restore CA5350
        var newGuid = new byte[16];
        Array.Copy(hash, 0, newGuid, 0, 16);
        newGuid[6] = (byte)((newGuid[6] & 0x0F) | 0x50);
        newGuid[8] = (byte)((newGuid[8] & 0x3F) | 0x80);
        SwapByteOrder(newGuid);
        return new Guid(newGuid);
    }

    private static void SwapByteOrder(byte[] guid)
    {
        (guid[0], guid[3]) = (guid[3], guid[0]);
        (guid[1], guid[2]) = (guid[2], guid[1]);
        (guid[4], guid[5]) = (guid[5], guid[4]);
        (guid[6], guid[7]) = (guid[7], guid[6]);
    }
}
