namespace Aumbrye.Procedural.Models;

public sealed record DungeonDefinition(
    int SchemaVersion,
    Guid RunId,
    int Seed,
    string BiomeId,
    int Tier,
    int PlayerLevelSnapshot,
    IReadOnlyList<DungeonRoom> Rooms,
    IReadOnlyList<DungeonEdge> Edges,
    DungeonPlacements Placements,
    DungeonBudgets Budgets,
    int FloorIndex = 1,
    bool IsFinalFloor = false,
    IReadOnlyList<object>? RoomContent = null,
    IReadOnlyList<object>? Locks = null,
    IReadOnlyList<object>? Puzzles = null,
    string? Checksum = null);

public sealed record DungeonRoom(
    string Id,
    string TemplateId,
    string Type,
    DungeonTransform Transform,
    IReadOnlyList<string> Tags);

public sealed record DungeonTransform(double X, double Y, double Z, double Yaw);

public sealed record DungeonEdge(string From, string To, string Kind);

public sealed record DungeonPlacements(
    IReadOnlyList<EnemyPlacement> Enemies,
    IReadOnlyList<LootPlacement> Loot,
    IReadOnlyList<object> Puzzles,
    IReadOnlyList<TrapPlacement> Traps,
    IReadOnlyList<SecretPlacement> Secrets,
    BossPlacement? Boss,
    string? Exit,
    string Entrance);

public sealed record EnemyPlacement(
    string RoomId,
    string EnemyId,
    Position3 Placement);

public sealed record LootPlacement(
    string RoomId,
    string ChestId,
    Position3 Position,
    IReadOnlyList<LootItem> Items);

public sealed record LootItem(string ItemId, int Quantity, string? InstanceId = null);

public sealed record TrapPlacement(string RoomId, string TrapId, Position3 Position);

public sealed record SecretPlacement(string RoomId);

public sealed record BossPlacement(string RoomId, string EnemyId);

public sealed record Position3(double X, double Y, double Z);

public sealed record DungeonBudgets(double EnemyThreat, double LootValue);
