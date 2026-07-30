using System.Text.Json;

namespace Aumbrye.Procedural.Content;

public static class TalentCatalog
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private static readonly Lazy<TalentTree> Tree = new(Load);

    public static TalentTree GetTree() => Tree.Value;

    private static TalentTree Load()
    {
        var path = Path.Combine(ContentPaths.Root, "talents", "tree.json");
        var json = File.ReadAllText(path);
        var raw = JsonSerializer.Deserialize<TalentTreeJson>(json, JsonOptions)
                  ?? throw new InvalidOperationException("Failed to parse talent tree.");
        return raw.ToModel();
    }
}

public sealed record TalentTree(
    int TalentPointsPerLevel,
    IReadOnlyList<TalentBranch> Branches)
{
    private readonly Lazy<Dictionary<string, TalentNode>> _nodesById = new(() =>
        Branches.SelectMany(b => b.Nodes).ToDictionary(n => n.Id, StringComparer.Ordinal));

    public bool TryGetNode(string nodeId, out TalentNode? node) =>
        _nodesById.Value.TryGetValue(nodeId, out node);

    public IEnumerable<TalentNode> AllNodes => _nodesById.Value.Values;
}

public sealed record TalentBranch(string Id, string NameKey, IReadOnlyList<TalentNode> Nodes);

public sealed record TalentNode(
    string Id,
    string NameKey,
    int MaxRank,
    int CostPerRank,
    IReadOnlyList<string> Requires);

internal sealed class TalentTreeJson
{
    public int TalentPointsPerLevel { get; set; } = 1;
    public List<TalentBranchJson> Branches { get; set; } = [];

    public TalentTree ToModel() => new(
        TalentPointsPerLevel,
        Branches.Select(b => b.ToModel()).ToList());
}

internal sealed class TalentBranchJson
{
    public string Id { get; set; } = "";
    public string NameKey { get; set; } = "";
    public List<TalentNodeJson> Nodes { get; set; } = [];

    public TalentBranch ToModel() => new(Id, NameKey, Nodes.Select(n => n.ToModel()).ToList());
}

internal sealed class TalentNodeJson
{
    public string Id { get; set; } = "";
    public string NameKey { get; set; } = "";
    public int MaxRank { get; set; } = 1;
    public int CostPerRank { get; set; } = 1;
    public List<string> Requires { get; set; } = [];

    public TalentNode ToModel() => new(Id, NameKey, MaxRank, CostPerRank, Requires);
}
