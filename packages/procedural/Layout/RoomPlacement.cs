using Aumbrye.Procedural.Assignment;
using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Models;
using Aumbrye.Procedural.Validation;
using static Aumbrye.Procedural.Biome.RoomTemplateCatalog;

namespace Aumbrye.Procedural.Layout;

/// <summary>
/// Places room centers so opposing doorway sockets meet.
/// </summary>
public static class RoomPlacement
{
    public static IReadOnlyList<DungeonRoom> BuildRooms(LayoutGraph graph, RoomAssignmentResult assignment)
    {
        var nodesById = graph.Nodes.ToDictionary(n => n.Id, StringComparer.Ordinal);
        var roomsByLayout = assignment.Rooms.ToDictionary(r => r.LayoutNodeId, StringComparer.Ordinal);
        var positions = new Dictionary<string, (double X, double Z)>(StringComparer.Ordinal);
        var visited = new HashSet<string>(StringComparer.Ordinal);
        var adjacency = ConnectivityValidator.BuildAdjacency(graph);
        var queue = new Queue<string>();

        positions[assignment.EntranceLayoutId] = (0, 0);
        visited.Add(assignment.EntranceLayoutId);
        queue.Enqueue(assignment.EntranceLayoutId);

        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            var currentNode = nodesById[current];
            var (px, pz) = positions[current];
            var parentSpec = GetRequired(roomsByLayout[current].TemplateId);

            foreach (var next in adjacency[current])
            {
                if (visited.Contains(next))
                    continue;

                var nextNode = nodesById[next];
                var dx = nextNode.GridX - currentNode.GridX;
                var dz = nextNode.GridZ - currentNode.GridZ;
                var (parentDoor, childDoor) = DoorsForStep(dx, dz);
                var childSpec = GetRequired(roomsByLayout[next].TemplateId);

                if (!parentSpec.HasDoor(parentDoor) || !childSpec.HasDoor(childDoor))
                {
                    throw new InvalidOperationException(
                        $"Door mismatch {roomsByLayout[current].TemplateId}→{roomsByLayout[next].TemplateId} " +
                        $"on step ({dx},{dz}).");
                }

                var (nx, nz) = (px, pz);
                if (dz == -1)
                    nz = pz - parentSpec.HalfDepth - childSpec.HalfDepth;
                else if (dz == 1)
                    nz = pz + parentSpec.HalfDepth + childSpec.HalfDepth;
                else if (dx == 1)
                    nx = px + parentSpec.HalfWidth + childSpec.HalfWidth;
                else if (dx == -1)
                    nx = px - parentSpec.HalfWidth - childSpec.HalfWidth;

                positions[next] = (nx, nz);
                visited.Add(next);
                queue.Enqueue(next);
            }
        }

        if (visited.Count != graph.Nodes.Count)
            throw new InvalidOperationException("Layout graph is disconnected.");

        return assignment.Rooms
            .OrderBy(r => r.SemanticId, StringComparer.Ordinal)
            .Select(r =>
            {
                var (x, z) = positions[r.LayoutNodeId];
                return new DungeonRoom(
                    r.SemanticId,
                    r.TemplateId,
                    r.Type,
                    new DungeonTransform(x, 0, z, 0),
                    r.Tags);
            })
            .ToList();
    }

    public static void ValidateDoorTopology(LayoutGraph graph, RoomAssignmentResult assignment)
    {
        var nodesById = graph.Nodes.ToDictionary(n => n.Id, StringComparer.Ordinal);
        var roomsByLayout = assignment.Rooms.ToDictionary(r => r.LayoutNodeId, StringComparer.Ordinal);
        var adjacency = ConnectivityValidator.BuildAdjacency(graph);

        foreach (var (layoutId, neighbors) in adjacency)
        {
            var node = nodesById[layoutId];
            var parentSpec = GetRequired(roomsByLayout[layoutId].TemplateId);
            foreach (var next in neighbors)
            {
                var nextNode = nodesById[next];
                var dx = nextNode.GridX - node.GridX;
                var dz = nextNode.GridZ - node.GridZ;
                var (parentDoor, childDoor) = DoorsForStep(dx, dz);
                var childSpec = GetRequired(roomsByLayout[next].TemplateId);
                if (!parentSpec.HasDoor(parentDoor) || !childSpec.HasDoor(childDoor))
                {
                    throw new InvalidOperationException(
                        $"Door topology invalid: {roomsByLayout[layoutId].TemplateId}↔{roomsByLayout[next].TemplateId} ({dx},{dz}).");
                }
            }
        }
    }
}
