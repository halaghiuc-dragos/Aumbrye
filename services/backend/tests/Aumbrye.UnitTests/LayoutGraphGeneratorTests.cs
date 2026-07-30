using Aumbrye.Procedural.Layout;
using Xunit;

namespace Aumbrye.UnitTests;

public class LayoutGraphGeneratorTests
{
    private static readonly BiomeLayoutRules Rules = BiomeLayoutRules.ForgottenCastle;

    [Fact]
    public void SameSeed_ProducesIdenticalGraph()
    {
        var a = LayoutGraphGenerator.Generate(Rules, 42_001);
        var b = LayoutGraphGenerator.Generate(Rules, 42_001);
        Assert.Equal(a.CanonicalFingerprint(), b.CanonicalFingerprint());
    }

    [Theory]
    [InlineData(1)]
    [InlineData(99)]
    [InlineData(123_456)]
    [InlineData(-7)]
    public void RoomCount_StaysWithinBiomeBounds(int seed)
    {
        var graph = LayoutGraphGenerator.Generate(Rules, seed);
        Assert.InRange(graph.Nodes.Count, Rules.RoomCountMin, Rules.RoomCountMax);
    }

    [Fact]
    public void Graph_IsConnected()
    {
        var graph = LayoutGraphGenerator.Generate(Rules, 7_777);
        var adjacency = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        foreach (var node in graph.Nodes)
            adjacency[node.Id] = new HashSet<string>(StringComparer.Ordinal);
        foreach (var edge in graph.Edges)
        {
            adjacency[edge.From].Add(edge.To);
            adjacency[edge.To].Add(edge.From);
        }

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

        Assert.Equal(graph.Nodes.Count, visited.Count);
    }

    [Fact]
    public void HundredSeeds_GenerateWithoutException()
    {
        for (var seed = 0; seed < 100; seed++)
            LayoutGraphGenerator.Generate(Rules, seed);
    }
}
