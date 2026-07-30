namespace Aumbrye.Procedural.Biome;

using Aumbrye.Procedural.Layout;
using Aumbrye.Procedural.Validation;

/// <summary>
/// Castle room kit dimensions and doorway sides (mirrors Godot scenes + CASTLE_ROOM_SOCKETS.md).
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

    private static readonly Dictionary<string, RoomSpec> Specs = new(StringComparer.Ordinal)
    {
        ["castle_entrance"] = new(16, 12, Doors.South),
        ["castle_stairs"] = new(8, 16, Doors.North | Doors.South),
        ["castle_courtyard"] = new(20, 20, Doors.North | Doors.South | Doors.East | Doors.West),
        ["castle_hall"] = new(16, 16, Doors.East | Doors.South | Doors.West),
        ["castle_treasure"] = new(10, 10, Doors.North),
        ["castle_secret"] = new(8, 8, Doors.East),
        ["castle_arena"] = new(24, 24, Doors.South | Doors.West),
        ["castle_boss"] = new(28, 28, Doors.North),
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

    public static string PickTemplateForDoors(string preferredTemplateId, Doors requiredDoors)
    {
        if (SupportsDoors(preferredTemplateId, requiredDoors))
            return preferredTemplateId;

        foreach (var templateId in new[] { "castle_hall", "castle_arena", "castle_courtyard" })
        {
            if (SupportsDoors(templateId, requiredDoors))
                return templateId;
        }

        return "castle_courtyard";
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
}
