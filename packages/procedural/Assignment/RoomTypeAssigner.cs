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
    IReadOnlyList<string> SecretLayoutIds,
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
        {
            bossCandidates = graph.Nodes
                .Where(n => n.Id != entranceLayoutId)
                .OrderByDescending(n => n.GridZ)
                .ThenBy(n => n.Id, StringComparer.Ordinal)
                .Select(n => n.Id)
                .ToList();
        }
        if (bossCandidates.Count == 0)
            throw new InvalidOperationException("No valid boss placement (north door requires southern neighbor).");
        var bossLayoutId = bossCandidates
            .OrderByDescending(id => distances[id])
            .ThenBy(id => id, StringComparer.Ordinal)
            .First();

        var secretLayoutIds = PickSecretNodes(graph, distances, entranceLayoutId, bossLayoutId, rng, maxSecrets: 2, biome.RequiresSecret);
        var treasureLayoutId = PickTreasureNode(graph, distances, entranceLayoutId, bossLayoutId, secretLayoutIds, rng);
        var corridorLayoutId = PickCorridorNeighbor(graph, entranceLayoutId, rng);
        var obstacleLayoutId = PickObstacleNode(
            graph, distances, entranceLayoutId, bossLayoutId, secretLayoutIds, treasureLayoutId, corridorLayoutId, rng);

        var assigned = new List<AssignedRoom>();
        var combatIndex = 0;
        foreach (var node in graph.Nodes.OrderBy(n => n.Id, StringComparer.Ordinal))
        {
            var (semanticId, templateId, type, tags) = ResolveRoom(
                graph,
                node.Id,
                entranceLayoutId,
                bossLayoutId,
                secretLayoutIds,
                treasureLayoutId,
                corridorLayoutId,
                obstacleLayoutId,
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
                var kind = ResolveEdgeKind(e, secretLayoutIds, assigned);
                return (fromSemantic, toSemantic, kind);
            })
            .OrderBy(e => e.fromSemantic, StringComparer.Ordinal)
            .ThenBy(e => e.toSemantic, StringComparer.Ordinal)
            .ToList();

        return new RoomAssignmentResult(
            assigned,
            entranceLayoutId,
            bossLayoutId,
            secretLayoutIds,
            edges);
    }

    private static (string SemanticId, string TemplateId, string Type, IReadOnlyList<string> Tags) ResolveRoom(
        LayoutGraph graph,
        string layoutId,
        string entranceId,
        string bossId,
        IReadOnlyList<string> secretIds,
        string treasureId,
        string corridorId,
        string? obstacleId,
        string prefix,
        Dictionary<string, string> combatPreferred,
        BiomeDefinition biome,
        ref int combatIndex)
    {
        if (layoutId == entranceId)
            return ("entrance", $"{prefix}_entrance", "hub", ["spawn"]);

        if (layoutId == bossId)
            return ("boss", $"{prefix}_boss", "boss", ["exit_portal"]);

        if (secretIds.Contains(layoutId))
        {
            var secretIndex = 0;
            for (var i = 0; i < secretIds.Count; i++)
            {
                if (secretIds[i] == layoutId)
                {
                    secretIndex = i;
                    break;
                }
            }
            var secretSemantic = secretIds.Count > 1 ? $"secret_{secretIndex + 1}" : "secret";
            return (secretSemantic, $"{prefix}_secret", "secret", ["secret_room"]);
        }

        if (layoutId == treasureId)
        {
            var treasureDoors = RequiredDoorsForNode(graph, layoutId);
            var treasureTemplate = PickTemplateForDoors($"{prefix}_treasure", treasureDoors, biome.RoomTemplateIds);
            return ("treasure", treasureTemplate, "treasure", []);
        }

        if (layoutId == corridorId)
            return ("stairs", $"{prefix}_stairs", "corridor", []);

        if (obstacleId != null && layoutId == obstacleId)
        {
            var obstacleDoors = RequiredDoorsForNode(graph, layoutId);
            var obstacleTemplate = PickTemplateForDoors($"{prefix}_puzzle", obstacleDoors, biome.RoomTemplateIds);
            return ("obstacle", obstacleTemplate, "obstacle", ["traversal"]);
        }

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
            "frozen_fortress" => "frozen",
            "dark_cathedral" => "cathedral",
            "iron_vault" => "vault",
            "prism_depths" => "prism",
            "venom_mire" => "mire",
            "glacial_hollow" => "hollow",
            "umbral_chapel" => "umbral",
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
        IReadOnlyList<string> secretLayoutIds,
        IReadOnlyList<AssignedRoom> rooms)
    {
        if (secretLayoutIds.Any(id => edge.From == id || edge.To == id))
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

    private static List<string> PickSecretNodes(
        LayoutGraph graph,
        Dictionary<string, int> distances,
        string entranceId,
        string bossId,
        SeededRandom rng,
        int maxSecrets = 2,
        bool requiresAtLeastOne = false)
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
            return [];
        candidates = candidates.OrderBy(id => id, StringComparer.Ordinal).ToList();
        var maxPick = Math.Min(2, candidates.Count);
        var minPick = requiresAtLeastOne && maxPick > 0 ? 1 : 0;
        var count = rng.NextInt(minPick, maxPick + 1);
        var picked = new List<string>();
        var pool = candidates.ToList();
        for (var i = 0; i < count; i++)
        {
            var idx = rng.NextInt(pool.Count);
            picked.Add(pool[idx]);
            pool.RemoveAt(idx);
        }
        return picked;
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
        IReadOnlyList<string> secretIds,
        SeededRandom rng)
    {
        var nodesById = graph.Nodes.ToDictionary(n => n.Id, StringComparer.Ordinal);
        var adjacency = ConnectivityValidator.BuildAdjacency(graph);
        var secretSet = secretIds.ToHashSet(StringComparer.Ordinal);
        var candidates = graph.Nodes
            .Where(n => n.Id != entranceId && n.Id != bossId && !secretSet.Contains(n.Id) && distances[n.Id] >= 2)
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
                .Where(n => n.Id != entranceId && n.Id != bossId && !secretSet.Contains(n.Id))
                .Select(n => n.Id)
                .ToList();
        }
        candidates.Sort(StringComparer.Ordinal);
        return candidates[rng.NextInt(candidates.Count)];
    }

    private static string? PickObstacleNode(
        LayoutGraph graph,
        Dictionary<string, int> distances,
        string entranceId,
        string bossId,
        IReadOnlyList<string> secretIds,
        string treasureId,
        string corridorId,
        SeededRandom rng)
    {
        var secretSet = secretIds.ToHashSet(StringComparer.Ordinal);
        var candidates = graph.Nodes
            .Where(n => n.Id != entranceId && n.Id != bossId && n.Id != treasureId && n.Id != corridorId)
            .Where(n => !secretSet.Contains(n.Id) && distances[n.Id] >= 2)
            .Select(n => n.Id)
            .ToList();
        if (candidates.Count == 0)
            return null;
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
