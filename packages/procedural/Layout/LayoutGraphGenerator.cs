using Aumbrye.Procedural.Random;

namespace Aumbrye.Procedural.Layout;

/// <summary>
/// PROC-3.1 — grow a connected grid graph from a seeded RNG.
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
            var pick = rng.NextInt(frontier.Count);
            var (cx, cz) = frontier[pick];
            var fromId = cells[(cx, cz)];

            var dirs = Directions.ToList();
            // Entrance only has a south door — first expansion must go south.
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
                // Keep the entrance→stairs spine linear; branch east/west from row 2+.
                if (dx != 0 && cz < 2)
                    continue;

                var newId = $"room_{nextIndex++}";
                cells[(nx, nz)] = newId;
                frontier.Add((nx, nz));
                edges.Add(new LayoutEdge(fromId, newId));
                expanded = true;
                if (fromId == "room_0")
                {
                    // Entrance has only a south doorway — never branch again from hub.
                    frontier.RemoveAt(pick);
                }
                break;
            }

            if (!expanded)
                frontier.RemoveAt(pick);
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
