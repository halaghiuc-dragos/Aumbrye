using Aumbrye.Procedural.Layout;

namespace Aumbrye.Procedural.Validation;

public sealed record ConnectivityValidationResult(bool IsValid, string? FailureReason = null)
{
    public static ConnectivityValidationResult Ok() => new(true);
    public static ConnectivityValidationResult Fail(string reason) => new(false, reason);
}

/// <summary>
/// PROC-3.2 — validate entrance → boss → exit path and placement invariants.
/// </summary>
public static class ConnectivityValidator
{
    public static ConnectivityValidationResult Validate(
        LayoutGraph graph,
        string entranceNodeId,
        string bossNodeId,
        bool requiresSecret,
        IReadOnlyList<string> secretNodeIds)
    {
        if (graph.Nodes.Count == 0)
            return ConnectivityValidationResult.Fail("Graph has no nodes.");

        var nodeIds = graph.Nodes.Select(n => n.Id).ToHashSet(StringComparer.Ordinal);
        if (!nodeIds.Contains(entranceNodeId))
            return ConnectivityValidationResult.Fail($"Entrance node {entranceNodeId} missing.");
        if (!nodeIds.Contains(bossNodeId))
            return ConnectivityValidationResult.Fail($"Boss node {bossNodeId} missing.");

        if (AreAdjacent(graph, entranceNodeId, bossNodeId))
            return ConnectivityValidationResult.Fail("Boss is adjacent to entrance.");

        var adjacency = BuildAdjacency(graph);
        if (!IsReachable(adjacency, entranceNodeId, bossNodeId))
            return ConnectivityValidationResult.Fail("No path from entrance to boss.");

        if (requiresSecret)
        {
            if (secretNodeIds == null || secretNodeIds.Count == 0)
                return ConnectivityValidationResult.Fail("Secret room required but not assigned.");
            foreach (var sid in secretNodeIds)
            {
                if (!nodeIds.Contains(sid))
                    return ConnectivityValidationResult.Fail($"Secret node {sid} missing.");
            }
            if (secretNodeIds.Count > 2)
                return ConnectivityValidationResult.Fail("More than 2 secret rooms assigned.");
        }

        if (!IsConnected(graph, adjacency))
            return ConnectivityValidationResult.Fail("Graph is disconnected.");

        return ConnectivityValidationResult.Ok();
    }

    public static bool AreAdjacent(LayoutGraph graph, string a, string b)
    {
        foreach (var edge in graph.Edges)
        {
            if ((edge.From == a && edge.To == b) || (edge.From == b && edge.To == a))
                return true;
        }
        return false;
    }

    public static Dictionary<string, HashSet<string>> BuildAdjacency(LayoutGraph graph)
    {
        var adjacency = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        foreach (var node in graph.Nodes)
            adjacency[node.Id] = new HashSet<string>(StringComparer.Ordinal);
        foreach (var edge in graph.Edges)
        {
            adjacency[edge.From].Add(edge.To);
            adjacency[edge.To].Add(edge.From);
        }
        return adjacency;
    }

    public static bool IsReachable(Dictionary<string, HashSet<string>> adjacency, string from, string to)
    {
        var visited = new HashSet<string>(StringComparer.Ordinal);
        var queue = new Queue<string>();
        queue.Enqueue(from);
        visited.Add(from);
        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            if (current == to)
                return true;
            foreach (var next in adjacency[current])
            {
                if (visited.Add(next))
                    queue.Enqueue(next);
            }
        }
        return false;
    }

    private static bool IsConnected(LayoutGraph graph, Dictionary<string, HashSet<string>> adjacency)
    {
        if (graph.Nodes.Count == 0)
            return true;
        var start = graph.Nodes[0].Id;
        var visited = new HashSet<string>(StringComparer.Ordinal);
        var queue = new Queue<string>();
        queue.Enqueue(start);
        visited.Add(start);
        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            foreach (var next in adjacency[current])
            {
                if (visited.Add(next))
                    queue.Enqueue(next);
            }
        }
        return visited.Count == graph.Nodes.Count;
    }
}
