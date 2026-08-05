using Aumbrye.Procedural.Random;

namespace Aumbrye.Procedural.Layout;

/// <summary>
/// PROC-3.1 — legacy grid graph grower.
/// GDScript RoomGraphGenerator is authoritative; kept for backend/CLI smoke tests.
/// </summary>
public static class LayoutGraphGenerator
{
    private static readonly (int Dx, int Dz)[] Directions =
    [
        (0, -1),
        (0, 1),
        (1, 0),
        (-1, 0),
    ];

    public static LayoutGraph Generate(BiomeLayoutRules rules, int seed)
    {
        var rng = new SeededRandom(seed);
        var targetRooms = rng.NextInt(rules.RoomCountMin, rules.RoomCountMax + 1);

        var cells = new Dictionary<(int X, int Z), string> { [(0, 0)] = "room_0" };
        var frontier = new List<(int X, int Z)> { (0, 0) };
        var edges = new List<LayoutEdge>();
        var nextIndex = 1;

        while (cells.Count < targetRooms && frontier.Count > 0)
        {
            rng.Shuffle(frontier);
            var expandedAny = false;

            for (var pick = frontier.Count - 1; pick >= 0 && cells.Count < targetRooms; pick--)
            {
                var (cx, cz) = frontier[pick];
                var fromId = cells[(cx, cz)];

                var dirs = Directions.ToList();
                if (cells.Count == 1)
                    dirs = [(0, 1)];
                else
                    rng.Shuffle(dirs);

                var expanded = false;
                foreach (var (dx, dz) in dirs)
                {
                    var nx = cx + dx;
                    var nz = cz + dz;
                    if (cells.ContainsKey((nx, nz)))
                        continue;
                    if (dx != 0 && cz < 1)
                        continue;

                    var newId = $"room_{nextIndex++}";
                    cells[(nx, nz)] = newId;
                    frontier.Add((nx, nz));
                    edges.Add(new LayoutEdge(fromId, newId));
                    expanded = true;
                    expandedAny = true;
                    if (fromId == "room_0")
                        frontier.RemoveAt(pick);
                    break;
                }

                if (!expanded)
                    frontier.RemoveAt(pick);
            }

            if (!expandedAny)
                break;
        }

        var nodes = cells
            .OrderBy(kv => kv.Value, StringComparer.Ordinal)
            .Select(kv => new LayoutNode(kv.Value, kv.Key.X, kv.Key.Z))
            .ToList();

        edges.Sort((a, b) =>
        {
            var from = string.CompareOrdinal(a.From, b.From);
            return from != 0 ? from : string.CompareOrdinal(a.To, b.To);
        });

        return new LayoutGraph(nodes, edges);
    }
}
