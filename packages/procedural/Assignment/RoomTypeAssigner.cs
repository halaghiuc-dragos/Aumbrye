using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Layout;
using Aumbrye.Procedural.Random;
using Aumbrye.Procedural.Validation;
using static Aumbrye.Procedural.Biome.RoomTemplateCatalog;

namespace Aumbrye.Procedural.Assignment;

public sealed record AssignedRoom(
    string LayoutNodeId,
    string SemanticId,
    string TemplateId,
    string Type,
    IReadOnlyList<string> Tags);

public sealed record RoomAssignmentResult(
    IReadOnlyList<AssignedRoom> Rooms,
    string EntranceLayoutId,
    string BossLayoutId,
    string? SecretLayoutId,
    IReadOnlyList<(string From, string To, string Kind)> Edges);

/// <summary>
/// PROC-3.3 — assign room types and semantic ids from layout graph.
/// </summary>
public static class RoomTypeAssigner
{
    private static readonly string[] CombatSemanticIds = ["courtyard", "hall", "arena"];

    private static readonly Dictionary<string, string> CombatPreferredTemplates = new(StringComparer.Ordinal)
    {
        ["courtyard"] = "castle_courtyard",
        ["hall"] = "castle_hall",
        ["arena"] = "castle_arena",
    };

    // Legacy castle defaults kept for tests referencing static map.

    public static RoomAssignmentResult Assign(BiomeDefinition biome, LayoutGraph graph, SeededRandom rng)
    {
        var prefix = TemplatePrefixForBiome(biome.Id);
        var combatPreferred = BuildCombatPreferred(prefix);
        var entranceLayoutId = graph.Nodes[0].Id;
        var distances = ComputeDistances(graph, entranceLayoutId);
        var nodesById = graph.Nodes.ToDictionary(n => n.Id, StringComparer.Ordinal);
        var adjacency = ConnectivityValidator.BuildAdjacency(graph);
        var bossCandidates = distances.Keys
            .Where(id => adjacency[id].Count > 0 && adjacency[id].All(nb => nodesById[nb].GridZ < nodesById[id].GridZ))
            .ToList();
        if (bossCandidates.Count == 0)
            throw new InvalidOperationException("No valid boss placement (north door requires southern neighbor).");
        var bossLayoutId = bossCandidates
            .OrderByDescending(id => distances[id])
            .ThenBy(id => id, StringComparer.Ordinal)
            .First();

        var secretLayoutId = PickSecretNode(graph, distances, entranceLayoutId, bossLayoutId, rng);
        var treasureLayoutId = PickTreasureNode(graph, distances, entranceLayoutId, bossLayoutId, secretLayoutId, rng);
        var corridorLayoutId = PickCorridorNeighbor(graph, entranceLayoutId, rng);

        var assigned = new List<AssignedRoom>();
        var combatIndex = 0;
        foreach (var node in graph.Nodes.OrderBy(n => n.Id, StringComparer.Ordinal))
        {
            var (semanticId, templateId, type, tags) = ResolveRoom(
                graph,
                node.Id,
                entranceLayoutId,
                bossLayoutId,
                secretLayoutId,
                treasureLayoutId,
                corridorLayoutId,
                prefix,
                combatPreferred,
                biome,
                ref combatIndex);

            assigned.Add(new AssignedRoom(node.Id, semanticId, templateId, type, tags));
        }

        var edges = graph.Edges
            .Select(e =>
            {
                var fromSemantic = assigned.First(r => r.LayoutNodeId == e.From).SemanticId;
                var toSemantic = assigned.First(r => r.LayoutNodeId == e.To).SemanticId;
                var kind = ResolveEdgeKind(e, secretLayoutId, assigned);
                return (fromSemantic, toSemantic, kind);
            })
            .OrderBy(e => e.fromSemantic, StringComparer.Ordinal)
            .ThenBy(e => e.toSemantic, StringComparer.Ordinal)
            .ToList();

        return new RoomAssignmentResult(
            assigned,
            entranceLayoutId,
            bossLayoutId,
            secretLayoutId,
            edges);
    }

    private static (string SemanticId, string TemplateId, string Type, IReadOnlyList<string> Tags) ResolveRoom(
        LayoutGraph graph,
        string layoutId,
        string entranceId,
        string bossId,
        string? secretId,
        string treasureId,
        string corridorId,
        string prefix,
        Dictionary<string, string> combatPreferred,
        BiomeDefinition biome,
        ref int combatIndex)
    {
        if (layoutId == entranceId)
            return ("entrance", $"{prefix}_entrance", "hub", ["spawn"]);

        if (layoutId == bossId)
            return ("boss", $"{prefix}_boss", "boss", ["exit_portal"]);

        if (secretId != null && layoutId == secretId)
            return ("secret", $"{prefix}_secret", "secret", ["secret_room"]);

        if (layoutId == treasureId)
            return ("treasure", $"{prefix}_treasure", "treasure", []);

        if (layoutId == corridorId)
            return ("stairs", $"{prefix}_stairs", "corridor", []);

        var semantic = combatIndex < CombatSemanticIds.Length
            ? CombatSemanticIds[combatIndex]
            : $"combat_{combatIndex}";
        combatIndex++;
        var requiredDoors = RequiredDoorsForNode(graph, layoutId);
        var preferred = combatPreferred.GetValueOrDefault(semantic, $"{prefix}_courtyard");
        var template = PickTemplateForDoors(preferred, requiredDoors, biome.RoomTemplateIds);
        return (semantic, template, "combat", []);
    }

    private static string TemplatePrefixForBiome(string biomeId) =>
        biomeId switch
        {
            "crystal_caverns" => "crystal",
            "poison_swamp" => "swamp",
            _ => "castle",
        };

    private static Dictionary<string, string> BuildCombatPreferred(string prefix) =>
        new(StringComparer.Ordinal)
        {
            ["courtyard"] = $"{prefix}_courtyard",
            ["hall"] = $"{prefix}_hall",
            ["arena"] = $"{prefix}_arena",
        };

    private static string ResolveEdgeKind(
        LayoutEdge edge,
        string? secretLayoutId,
        IReadOnlyList<AssignedRoom> rooms)
    {
        if (secretLayoutId != null &&
            (edge.From == secretLayoutId || edge.To == secretLayoutId))
            return "secret";

        var from = rooms.First(r => r.LayoutNodeId == edge.From);
        var to = rooms.First(r => r.LayoutNodeId == edge.To);
        if (from.Type == "corridor" || to.Type == "corridor")
            return "corridor";
        return "door";
    }

    private static Dictionary<string, int> ComputeDistances(LayoutGraph graph, string startId)
    {
        var adjacency = ConnectivityValidator.BuildAdjacency(graph);
        var distances = new Dictionary<string, int>(StringComparer.Ordinal);
        var queue = new Queue<string>();
        queue.Enqueue(startId);
        distances[startId] = 0;
        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            foreach (var next in adjacency[current])
            {
                if (distances.ContainsKey(next))
                    continue;
                distances[next] = distances[current] + 1;
                queue.Enqueue(next);
            }
        }
        foreach (var node in graph.Nodes)
            distances.TryAdd(node.Id, int.MaxValue);
        return distances;
    }

    private static string? PickSecretNode(
        LayoutGraph graph,
        Dictionary<string, int> distances,
        string entranceId,
        string bossId,
        SeededRandom rng)
    {
        var nodesById = graph.Nodes.ToDictionary(n => n.Id, StringComparer.Ordinal);
        var adjacency = ConnectivityValidator.BuildAdjacency(graph);
        var candidates = graph.Nodes
            .Where(n => n.Id != entranceId && n.Id != bossId && distances[n.Id] >= 2)
            .Where(n => adjacency[n.Id].Count > 0 && adjacency[n.Id].All(nb =>
            {
                var neighbor = nodesById[nb];
                return neighbor.GridX > n.GridX;
            }))
            .Select(n => n.Id)
            .ToList();
        if (candidates.Count == 0)
            return null;
        return candidates[rng.NextInt(candidates.Count)];
    }

    private static string PickTreasureNode(
        LayoutGraph graph,
        Dictionary<string, int> distances,
        string entranceId,
        string bossId,
        string? secretId,
        SeededRandom rng)
    {
        var nodesById = graph.Nodes.ToDictionary(n => n.Id, StringComparer.Ordinal);
        var adjacency = ConnectivityValidator.BuildAdjacency(graph);
        var candidates = graph.Nodes
            .Where(n => n.Id != entranceId && n.Id != bossId && n.Id != secretId && distances[n.Id] >= 2)
            .Where(n => adjacency[n.Id].Count > 0 && adjacency[n.Id].All(nb =>
            {
                var neighbor = nodesById[nb];
                return neighbor.GridZ < n.GridZ;
            }))
            .Select(n => n.Id)
            .ToList();
        if (candidates.Count == 0)
        {
            candidates = graph.Nodes
                .Where(n => n.Id != entranceId && n.Id != bossId)
                .Select(n => n.Id)
                .ToList();
        }
        candidates.Sort(StringComparer.Ordinal);
        return candidates[rng.NextInt(candidates.Count)];
    }

    private static string PickCorridorNeighbor(LayoutGraph graph, string entranceId, SeededRandom rng)
    {
        var entranceNode = graph.Nodes.First(n => n.Id == entranceId);
        var neighbors = graph.Edges
            .Where(e => e.From == entranceId || e.To == entranceId)
            .Select(e => e.From == entranceId ? e.To : e.From)
            .Where(nId =>
            {
                var node = graph.Nodes.First(n => n.Id == nId);
                return node.GridX == entranceNode.GridX && node.GridZ == entranceNode.GridZ + 1;
            })
            .Distinct(StringComparer.Ordinal)
            .ToList();
        if (neighbors.Count == 0)
            throw new InvalidOperationException("Entrance has no south corridor neighbor.");
        return neighbors[rng.NextInt(neighbors.Count)];
    }
}
