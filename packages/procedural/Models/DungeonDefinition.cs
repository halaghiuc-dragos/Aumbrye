using System.Text.Json;

namespace Aumbrye.Procedural.Models;

public sealed record RoomContentEntry(
    string RoomId,
    string ContentType,
    IReadOnlyDictionary<string, JsonElement> Params);

public sealed record DungeonLock(string RoomId, string LockId, string KeyItemId);

public sealed record DungeonPuzzle(string RoomId, string PuzzleId, string Kind);

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
    IReadOnlyList<RoomContentEntry>? RoomContent = null,
    IReadOnlyList<DungeonLock>? Locks = null,
    IReadOnlyList<DungeonPuzzle>? Puzzles = null,
    string? Checksum = null,
    IReadOnlyList<string>? GeneratorCapabilities = null);

/// <summary>
/// Which parts of a dungeon definition its generator actually filled in.
/// </summary>
/// <remarks>
/// Two generators produce definitions: the GDScript one (gameplay-authoritative, fills everything)
/// and this C# one (backend/CLI, layout and placements only). Without a declared capability set a
/// consumer cannot tell an intentionally empty <c>roomContent</c> from a floor that genuinely has
/// none, and a server-issued definition silently describes a different dungeon than the client
/// plays. See docs/ADR/0002-procgen-authority-split.md.
/// </remarks>
public static class GeneratorCapability
{
    /// <summary>Room graph, room transforms and edges.</summary>
    public const string Layout = "layout";

    /// <summary>Enemy, loot, trap, secret and boss placements.</summary>
    public const string Placements = "placements";

    /// <summary>Per-room content assignment (shrines, puzzles rooms, ambushes, …).</summary>
    public const string RoomContent = "roomContent";

    /// <summary>Lock/key gating across the room graph.</summary>
    public const string Locks = "locks";

    /// <summary>Puzzle instances bound to rooms.</summary>
    public const string Puzzles = "puzzles";

    /// <summary>What the C# generator emits today.</summary>
    public static readonly IReadOnlyList<string> CSharpBackend = [Layout, Placements];

    /// <summary>What the GDScript generator emits — the full gameplay surface.</summary>
    public static readonly IReadOnlyList<string> GdScriptClient =
        [Layout, Placements, RoomContent, Locks, Puzzles];
}

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
    IReadOnlyList<DungeonPuzzle> Puzzles,
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
