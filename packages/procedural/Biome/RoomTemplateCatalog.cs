namespace Aumbrye.Procedural.Biome;

using Aumbrye.Procedural.Layout;
using Aumbrye.Procedural.Validation;

/// <summary>
/// Castle room kit dimensions and doorway sides (mirrors Godot scenes).
/// </summary>
public static class RoomTemplateCatalog
{
    [Flags]
    public enum Doors
    {
        None = 0,
        North = 1,
        East = 2,
        South = 4,
        West = 8,
    }

    public sealed record RoomSpec(double Width, double Depth, Doors DoorMask)
    {
        public double HalfWidth => Width / 2;
        public double HalfDepth => Depth / 2;

        public bool HasDoor(Doors door) => (DoorMask & door) != 0;
    }

    private const Doors AllDoors = Doors.North | Doors.East | Doors.South | Doors.West;

    private static readonly Dictionary<string, RoomSpec> Specs = new(StringComparer.Ordinal)
    {
        ["castle_entrance"] = new(16, 12, AllDoors),
        ["castle_stairs"] = new(8, 16, AllDoors),
        ["castle_corridor"] = new(8, 12, Doors.North | Doors.South),
        ["castle_courtyard"] = new(20, 20, Doors.North | Doors.South | Doors.East | Doors.West),
        ["castle_hall"] = new(16, 16, AllDoors),
        ["castle_treasure"] = new(12, 12, Doors.North),
        ["castle_secret"] = new(8, 8, Doors.East),
        ["castle_arena"] = new(24, 24, Doors.South | Doors.West),
        ["castle_boss"] = new(28, 28, Doors.North),
        ["castle_puzzle"] = new(16, 16, AllDoors),

        // Crystal Caverns (M5)
        ["crystal_entrance"] = new(16, 12, AllDoors),
        ["crystal_stairs"] = new(8, 16, AllDoors),
        ["crystal_corridor"] = new(8, 12, Doors.North | Doors.South),
        ["crystal_courtyard"] = new(20, 20, Doors.North | Doors.South | Doors.East | Doors.West),
        ["crystal_hall"] = new(16, 16, AllDoors),
        ["crystal_treasure"] = new(12, 12, Doors.North),
        ["crystal_secret"] = new(8, 8, Doors.East),
        ["crystal_arena"] = new(24, 24, Doors.South | Doors.West),
        ["crystal_boss"] = new(28, 28, Doors.North),
        ["crystal_puzzle"] = new(16, 16, AllDoors),

        // Poison Swamp (M5)
        ["swamp_entrance"] = new(16, 12, AllDoors),
        ["swamp_stairs"] = new(8, 16, AllDoors),
        ["swamp_corridor"] = new(8, 12, Doors.North | Doors.South),
        ["swamp_courtyard"] = new(20, 20, Doors.North | Doors.South | Doors.East | Doors.West),
        ["swamp_hall"] = new(16, 16, AllDoors),
        ["swamp_treasure"] = new(12, 12, Doors.North),
        ["swamp_secret"] = new(8, 8, Doors.East),
        ["swamp_arena"] = new(24, 24, Doors.South | Doors.West),
        ["swamp_boss"] = new(28, 28, Doors.North),
        ["swamp_puzzle"] = new(16, 16, AllDoors),

        // Frozen Fortress (M6)
        ["frozen_entrance"] = new(16, 12, AllDoors),
        ["frozen_stairs"] = new(8, 16, AllDoors),
        ["frozen_corridor"] = new(8, 12, Doors.North | Doors.South),
        ["frozen_courtyard"] = new(20, 20, Doors.North | Doors.South | Doors.East | Doors.West),
        ["frozen_hall"] = new(16, 16, AllDoors),
        ["frozen_treasure"] = new(12, 12, Doors.North),
        ["frozen_secret"] = new(8, 8, Doors.East),
        ["frozen_arena"] = new(24, 24, Doors.South | Doors.West),
        ["frozen_boss"] = new(28, 28, Doors.North),
        ["frozen_puzzle"] = new(16, 16, AllDoors),

        // Dark Cathedral (M6)
        ["cathedral_entrance"] = new(16, 12, AllDoors),
        ["cathedral_stairs"] = new(8, 16, AllDoors),
        ["cathedral_corridor"] = new(8, 12, Doors.North | Doors.South),
        ["cathedral_courtyard"] = new(20, 20, Doors.North | Doors.South | Doors.East | Doors.West),
        ["cathedral_hall"] = new(16, 16, AllDoors),
        ["cathedral_treasure"] = new(12, 12, Doors.North),
        ["cathedral_secret"] = new(8, 8, Doors.East),
        ["cathedral_arena"] = new(24, 24, Doors.South | Doors.West),
        ["cathedral_boss"] = new(28, 28, Doors.North),
        ["cathedral_puzzle"] = new(16, 16, AllDoors),

        // Iron Vault (M7)
        ["vault_entrance"] = new(16, 12, AllDoors),
        ["vault_stairs"] = new(8, 16, AllDoors),
        ["vault_corridor"] = new(8, 12, Doors.North | Doors.South),
        ["vault_courtyard"] = new(20, 20, Doors.North | Doors.South | Doors.East | Doors.West),
        ["vault_hall"] = new(16, 16, AllDoors),
        ["vault_treasure"] = new(12, 12, Doors.North),
        ["vault_secret"] = new(8, 8, Doors.East),
        ["vault_arena"] = new(24, 24, Doors.South | Doors.West),
        ["vault_boss"] = new(28, 28, Doors.North),
        ["vault_puzzle"] = new(16, 16, AllDoors),

        // Prism Depths (M7)
        ["prism_entrance"] = new(16, 12, AllDoors),
        ["prism_stairs"] = new(8, 16, AllDoors),
        ["prism_corridor"] = new(8, 12, Doors.North | Doors.South),
        ["prism_courtyard"] = new(20, 20, Doors.North | Doors.South | Doors.East | Doors.West),
        ["prism_hall"] = new(16, 16, AllDoors),
        ["prism_treasure"] = new(12, 12, Doors.North),
        ["prism_secret"] = new(8, 8, Doors.East),
        ["prism_arena"] = new(24, 24, Doors.South | Doors.West),
        ["prism_boss"] = new(28, 28, Doors.North),
        ["prism_puzzle"] = new(16, 16, AllDoors),

        // Venom Mire (M7)
        ["mire_entrance"] = new(16, 12, AllDoors),
        ["mire_stairs"] = new(8, 16, AllDoors),
        ["mire_corridor"] = new(8, 12, Doors.North | Doors.South),
        ["mire_courtyard"] = new(20, 20, Doors.North | Doors.South | Doors.East | Doors.West),
        ["mire_hall"] = new(16, 16, AllDoors),
        ["mire_treasure"] = new(12, 12, Doors.North),
        ["mire_secret"] = new(8, 8, Doors.East),
        ["mire_arena"] = new(24, 24, Doors.South | Doors.West),
        ["mire_boss"] = new(28, 28, Doors.North),
        ["mire_puzzle"] = new(16, 16, AllDoors),

        // Glacial Hollow (M7)
        ["hollow_entrance"] = new(16, 12, AllDoors),
        ["hollow_stairs"] = new(8, 16, AllDoors),
        ["hollow_corridor"] = new(8, 12, Doors.North | Doors.South),
        ["hollow_courtyard"] = new(20, 20, Doors.North | Doors.South | Doors.East | Doors.West),
        ["hollow_hall"] = new(16, 16, AllDoors),
        ["hollow_treasure"] = new(12, 12, Doors.North),
        ["hollow_secret"] = new(8, 8, Doors.East),
        ["hollow_arena"] = new(24, 24, Doors.South | Doors.West),
        ["hollow_boss"] = new(28, 28, Doors.North),
        ["hollow_puzzle"] = new(16, 16, AllDoors),

        // Umbral Chapel (M7)
        ["umbral_entrance"] = new(16, 12, AllDoors),
        ["umbral_stairs"] = new(8, 16, AllDoors),
        ["umbral_corridor"] = new(8, 12, Doors.North | Doors.South),
        ["umbral_courtyard"] = new(20, 20, Doors.North | Doors.South | Doors.East | Doors.West),
        ["umbral_hall"] = new(16, 16, AllDoors),
        ["umbral_treasure"] = new(12, 12, Doors.North),
        ["umbral_secret"] = new(8, 8, Doors.East),
        ["umbral_arena"] = new(24, 24, Doors.South | Doors.West),
        ["umbral_boss"] = new(28, 28, Doors.North),
        ["umbral_puzzle"] = new(16, 16, AllDoors),
    };

    public static RoomSpec GetRequired(string templateId) =>
        Specs.TryGetValue(templateId, out var spec)
            ? spec
            : throw new ArgumentException($"Unknown room template '{templateId}'.");

    public static bool SupportsDoors(string templateId, Doors requiredDoors) =>
        (GetRequired(templateId).DoorMask & requiredDoors) == requiredDoors;

    public static Doors RequiredDoorsForNode(LayoutGraph graph, string layoutId)
    {
        var nodesById = graph.Nodes.ToDictionary(n => n.Id, StringComparer.Ordinal);
        var adjacency = ConnectivityValidator.BuildAdjacency(graph);
        var node = nodesById[layoutId];
        var required = Doors.None;
        foreach (var neighborId in adjacency[layoutId])
        {
            var neighbor = nodesById[neighborId];
            var dx = neighbor.GridX - node.GridX;
            var dz = neighbor.GridZ - node.GridZ;
            var (parentDoor, _) = DoorsForStep(dx, dz);
            required |= parentDoor;
        }
        return required;
    }

    public static string PickTemplateForDoors(string preferredTemplateId, Doors requiredDoors, IReadOnlyList<string>? biomeTemplates = null)
    {
        if (SupportsDoors(preferredTemplateId, requiredDoors))
            return preferredTemplateId;

        if (biomeTemplates is { Count: > 0 })
        {
            foreach (var templateId in biomeTemplates)
            {
                if (SupportsDoors(templateId, requiredDoors))
                    return templateId;
            }

            var prefix = biomeTemplates[0].Split('_')[0];
            foreach (var templateId in new[] { $"{prefix}_courtyard", $"{prefix}_hall", $"{prefix}_arena" })
            {
                if (Specs.ContainsKey(templateId) && SupportsDoors(templateId, requiredDoors))
                    return templateId;
            }
        }

        foreach (var templateId in new[] { "castle_hall", "castle_arena", "castle_courtyard" })
        {
            if (SupportsDoors(templateId, requiredDoors))
                return templateId;
        }

        return "castle_courtyard";
    }

    [Obsolete("Use overload with biome template list for non-castle biomes.")]
    public static string PickTemplateForDoors(string preferredTemplateId, Doors requiredDoors) =>
        PickTemplateForDoors(preferredTemplateId, requiredDoors, null);

    public static string TemplatePrefixForBiome(string biomeId)
    {
        if (BiomeCatalog.TryGet(biomeId, out var biome) && biome is not null)
            return biome.TemplatePrefix;
        return "castle";
    }

    /// <summary>Parent→child grid step; returns required door on parent and child.</summary>
    public static (Doors ParentDoor, Doors ChildDoor) DoorsForStep(int dx, int dz)
    {
        if (dx == 0 && dz == -1)
            return (Doors.North, Doors.South);
        if (dx == 0 && dz == 1)
            return (Doors.South, Doors.North);
        if (dx == 1 && dz == 0)
            return (Doors.East, Doors.West);
        if (dx == -1 && dz == 0)
            return (Doors.West, Doors.East);
        throw new ArgumentException($"Invalid grid step ({dx}, {dz}).");
    }

    public static double YawDegreesForIncomingDoor(string templateId, Doors incomingDoor)
    {
        var spec = GetRequired(templateId);
        var primary = PrimaryDoorMask(spec.DoorMask);
        if (primary == Doors.None || incomingDoor == Doors.None)
            return 0;
        return YawDegreesToAlignDoors(primary, incomingDoor);
    }

    public static double YawDegreesForEntrance(string templateId, Doors requiredDoors)
    {
        var spec = GetRequired(templateId);
        var primary = PrimaryDoorMask(spec.DoorMask);
        var required = FirstSetDoor(requiredDoors);
        if (primary == Doors.None || required == Doors.None)
            return 0;
        return YawDegreesToAlignDoors(primary, required);
    }

    public static double HalfExtentX(RoomSpec spec, double yawRad) =>
        spec.HalfWidth * Math.Abs(Math.Cos(yawRad)) + spec.HalfDepth * Math.Abs(Math.Sin(yawRad));

    public static double HalfExtentZ(RoomSpec spec, double yawRad) =>
        spec.HalfWidth * Math.Abs(Math.Sin(yawRad)) + spec.HalfDepth * Math.Abs(Math.Cos(yawRad));

    private static Doors PrimaryDoorMask(Doors doors)
    {
        if (doors == Doors.None)
            return Doors.None;
        if ((doors & (doors - 1)) == 0)
            return doors;
        return Doors.None;
    }

    private static Doors FirstSetDoor(Doors mask)
    {
        foreach (var door in new[] { Doors.North, Doors.East, Doors.South, Doors.West })
        {
            if ((mask & door) != 0)
                return door;
        }
        return Doors.None;
    }

    private static double YawDegreesToAlignDoors(Doors fromDoor, Doors toDoor) =>
        (DoorYawRadians(toDoor) - DoorYawRadians(fromDoor)) * 180.0 / Math.PI;

    private static double DoorYawRadians(Doors door) => door switch
    {
        Doors.North => 0,
        Doors.East => Math.PI / 2.0,
        Doors.South => Math.PI,
        Doors.West => -Math.PI / 2.0,
        _ => 0,
    };
}
