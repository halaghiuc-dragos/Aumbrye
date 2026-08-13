using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Aumbrye.Procedural.Models;

namespace Aumbrye.Procedural.Serialization;

/// <summary>
/// PROC-3.6 — canonical JSON with stable key ordering and checksum.
/// </summary>
public static class CanonicalJsonSerializer
{
    private static readonly JsonSerializerOptions IndentedOptions = new() { WriteIndented = false };

    public static (string Json, string Checksum) Serialize(DungeonDefinition definition)
    {
        // The canonical graph is built once and reused. The root is a SortedDictionary, so adding
        // "checksum" after hashing still emits it in the same ordinal position the two-pass build
        // produced — byte-identical output, without a second walk of a multi-KB object graph on
        // the run-creation and floor-transition hot path.
        var root = BuildCanonicalObject(definition with { Checksum = null });
        var checksum = ComputeChecksum(JsonSerializer.Serialize(root, IndentedOptions));
        root["checksum"] = checksum;
        return (JsonSerializer.Serialize(root, IndentedOptions), checksum);
    }

    public static string ComputeChecksum(string canonicalJsonWithoutChecksum)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(canonicalJsonWithoutChecksum));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    private static SortedDictionary<string, object?> BuildCanonicalObject(DungeonDefinition def)
    {
        var root = new SortedDictionary<string, object?>(StringComparer.Ordinal)
        {
            ["schemaVersion"] = def.SchemaVersion,
            ["runId"] = def.RunId.ToString(),
            ["seed"] = def.Seed,
            ["biomeId"] = def.BiomeId,
            ["tier"] = def.Tier,
            ["playerLevelSnapshot"] = def.PlayerLevelSnapshot,
            ["floorIndex"] = def.FloorIndex,
            ["isFinalFloor"] = def.IsFinalFloor,
            ["rooms"] = def.Rooms.Select(r => new SortedDictionary<string, object?>(StringComparer.Ordinal)
            {
                ["id"] = r.Id,
                ["templateId"] = r.TemplateId,
                ["type"] = r.Type,
                ["transform"] = TransformDict(r.Transform),
                ["tags"] = r.Tags.ToList(),
            }).ToList(),
            ["edges"] = def.Edges.Select(e => new SortedDictionary<string, object?>(StringComparer.Ordinal)
            {
                ["from"] = e.From,
                ["to"] = e.To,
                ["kind"] = e.Kind,
            }).ToList(),
            ["placements"] = PlacementsDict(def.Placements),
            ["budgets"] = new SortedDictionary<string, object?>(StringComparer.Ordinal)
            {
                ["enemyThreat"] = def.Budgets.EnemyThreat,
                ["lootValue"] = def.Budgets.LootValue,
            },
            ["roomContent"] = def.RoomContent?.Select(RoomContentDict).ToList() ?? [],
            ["locks"] = def.Locks?.Select(LockDict).ToList() ?? [],
            ["puzzles"] = def.Puzzles?.Select(PuzzleDict).ToList() ?? [],
            // Declares which sections this generator actually populated, so an empty roomContent
            // reads as "not my job" rather than "this floor has none".
            ["generatorCapabilities"] = def.GeneratorCapabilities?.ToList() ?? [],
        };
        if (def.Checksum != null)
            root["checksum"] = def.Checksum;
        return root;
    }

    private static SortedDictionary<string, object?> RoomContentDict(RoomContentEntry entry) =>
      new(StringComparer.Ordinal)
      {
          ["roomId"] = entry.RoomId,
          ["contentType"] = entry.ContentType,
          ["params"] = ParamsDict(entry.Params),
      };

    private static SortedDictionary<string, object?> LockDict(DungeonLock entry) =>
      new(StringComparer.Ordinal)
      {
          ["roomId"] = entry.RoomId,
          ["lockId"] = entry.LockId,
          ["keyItemId"] = entry.KeyItemId,
      };

    private static SortedDictionary<string, object?> PuzzleDict(DungeonPuzzle entry) =>
      new(StringComparer.Ordinal)
      {
          ["roomId"] = entry.RoomId,
          ["puzzleId"] = entry.PuzzleId,
          ["kind"] = entry.Kind,
      };

    private static SortedDictionary<string, object?> ParamsDict(IReadOnlyDictionary<string, JsonElement> parameters)
    {
        var dict = new SortedDictionary<string, object?>(StringComparer.Ordinal);
        foreach (var (key, value) in parameters.OrderBy(static p => p.Key, StringComparer.Ordinal))
            dict[key] = value;
        return dict;
    }

    private static SortedDictionary<string, object?> TransformDict(DungeonTransform t) =>
      new(StringComparer.Ordinal)
      {
          ["x"] = t.X,
          ["y"] = t.Y,
          ["z"] = t.Z,
          ["yaw"] = t.Yaw,
      };

    private static SortedDictionary<string, object?> PositionDict(Position3 p) =>
      new(StringComparer.Ordinal)
      {
          ["x"] = p.X,
          ["y"] = p.Y,
          ["z"] = p.Z,
      };

    private static SortedDictionary<string, object?> PlacementsDict(DungeonPlacements p)
    {
        var dict = new SortedDictionary<string, object?>(StringComparer.Ordinal)
        {
            ["enemies"] = p.Enemies.Select(e => new SortedDictionary<string, object?>(StringComparer.Ordinal)
            {
                ["roomId"] = e.RoomId,
                ["enemyId"] = e.EnemyId,
                ["position"] = PositionDict(e.Placement),
            }).ToList(),
            ["loot"] = p.Loot.Select(l => new SortedDictionary<string, object?>(StringComparer.Ordinal)
            {
                ["roomId"] = l.RoomId,
                ["chestId"] = l.ChestId,
                ["position"] = PositionDict(l.Position),
                ["items"] = l.Items.Select(i => new SortedDictionary<string, object?>(StringComparer.Ordinal)
                {
                    ["itemId"] = i.ItemId,
                    ["quantity"] = i.Quantity,
                    ["instanceId"] = i.InstanceId,
                }).ToList(),
            }).ToList(),
            ["puzzles"] = p.Puzzles.Select(PuzzleDict).ToList(),
            ["traps"] = p.Traps.Select(t => new SortedDictionary<string, object?>(StringComparer.Ordinal)
            {
                ["roomId"] = t.RoomId,
                ["trapId"] = t.TrapId,
                ["position"] = PositionDict(t.Position),
            }).ToList(),
            ["secrets"] = p.Secrets.Select(s => new SortedDictionary<string, object?>(StringComparer.Ordinal)
            {
                ["roomId"] = s.RoomId,
            }).ToList(),
            ["boss"] = p.Boss == null
            ? null
            : new SortedDictionary<string, object?>(StringComparer.Ordinal)
            {
                ["roomId"] = p.Boss.RoomId,
                ["enemyId"] = p.Boss.EnemyId,
            },
            ["exit"] = p.Exit,
            ["entrance"] = p.Entrance,
        };
        return dict;
    }
}
