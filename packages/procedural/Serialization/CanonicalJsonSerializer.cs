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

  public static string Serialize(DungeonDefinition definition)
  {
    var withoutChecksum = definition with { Checksum = null };
    var canonical = BuildCanonicalObject(withoutChecksum);
    var json = JsonSerializer.Serialize(canonical, IndentedOptions);
    var checksum = ComputeChecksum(json);
    var withChecksum = definition with { Checksum = checksum };
    return JsonSerializer.Serialize(BuildCanonicalObject(withChecksum), IndentedOptions);
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
      ["roomContent"] = def.RoomContent?.ToList() ?? new List<object>(),
      ["locks"] = def.Locks?.ToList() ?? new List<object>(),
      ["puzzles"] = def.Puzzles?.ToList() ?? new List<object>(),
    };
    if (def.Checksum != null)
      root["checksum"] = def.Checksum;
    return root;
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
      ["puzzles"] = p.Puzzles.ToList(),
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
