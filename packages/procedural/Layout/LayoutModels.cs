namespace Aumbrye.Procedural.Layout;

public sealed record LayoutNode(string Id, int GridX, int GridZ);

public sealed record LayoutEdge(string From, string To, string Kind = "corridor");

public sealed record LayoutGraph(IReadOnlyList<LayoutNode> Nodes, IReadOnlyList<LayoutEdge> Edges)
{
    public string CanonicalFingerprint()
    {
        var nodeLines = Nodes
            .OrderBy(n => n.Id, StringComparer.Ordinal)
            .Select(n => $"{n.Id}:{n.GridX},{n.GridZ}");
        var edgeLines = Edges
            .OrderBy(e => e.From, StringComparer.Ordinal)
            .ThenBy(e => e.To, StringComparer.Ordinal)
            .Select(e => $"{e.From}->{e.To}:{e.Kind}");
        return string.Join("|", nodeLines.Concat(edgeLines));
    }
}

public sealed record BiomeLayoutRules(
    string BiomeId,
    int RoomCountMin,
    int RoomCountMax,
    int GridStep = 14)
{
    public static BiomeLayoutRules ForgottenCastle { get; } = new(
        "forgotten_castle",
        RoomCountMin: 18,
        RoomCountMax: 22,
        GridStep: 14);
}
