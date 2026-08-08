using System.Text.Json;
using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Generation;
using Aumbrye.ProcgenCli;

if (args.Length == 0 || args[0] is "-h" or "--help")
{
    PrintUsage();
    return args.Length == 0 ? 1 : 0;
}

try
{
    return args[0] switch
    {
        "generate" => RunGenerate(args),
        "mix-seed-table" => RunMixSeedTable(),
        "room-kit-specs" => RunRoomKitSpecs(),
        _ => UnknownCommand(args[0]),
    };
}
catch (Exception ex)
{
    Console.Error.WriteLine(ex.Message);
    return 1;
}

static int RunGenerate(string[] args)
{
    var options = ProcgenCliArgs.ParseGenerateArgs(args);
    var result = DungeonGenerator.Generate(
        options.BiomeId,
        options.Seed,
        options.Tier,
        options.PlayerLevel,
        options.RunId,
        options.FloorIndex,
        options.IsFinalFloor);

    Console.Out.WriteLine(result.Json);
    return 0;
}

static int RunMixSeedTable()
{
    var seeds = new[] { 1, 2, 12345, 2147483646 };
    var rows = new List<Dictionary<string, int>>();
    foreach (var seed in seeds)
    {
        for (var floor = 1; floor <= 25; floor++)
        {
            rows.Add(new Dictionary<string, int>
            {
                ["seed"] = seed,
                ["floor"] = floor,
                ["mixed"] = DungeonSeedDeriver.MixFloorSeed(seed, floor),
            });
        }
    }
    Console.Out.WriteLine(JsonSerializer.Serialize(rows));
    return 0;
}

static int RunRoomKitSpecs()
{
    var prefixes = new[]
    {
    "castle", "crystal", "swamp", "frozen", "cathedral", "vault", "prism", "mire", "hollow", "umbral",
  };
    var kinds = new[]
    {
    "entrance", "stairs", "courtyard", "hall", "treasure", "secret", "arena", "boss", "puzzle",
  };
    var entries = new List<Dictionary<string, object>>();
    foreach (var prefix in prefixes)
    {
        foreach (var kind in kinds)
        {
            var templateId = $"{prefix}_{kind}";
            var spec = RoomTemplateCatalog.GetRequired(templateId);
            entries.Add(new Dictionary<string, object>
            {
                ["templateId"] = templateId,
                ["width"] = spec.Width,
                ["depth"] = spec.Depth,
                ["doors"] = (int)spec.DoorMask,
            });
        }
    }
    Console.Out.WriteLine(JsonSerializer.Serialize(entries));
    return 0;
}

static int UnknownCommand(string command)
{
    Console.Error.WriteLine($"Unknown command: {command}");
    PrintUsage();
    return 1;
}

static void PrintUsage()
{
    Console.Error.WriteLine("Aumbrye local dungeon generator");
    Console.Error.WriteLine("Usage:");
    Console.Error.WriteLine("  procgen-cli generate <biomeId> <seed> [runId] [--floor N] [--final-floor] [--tier N] [--player-level N]");
    Console.Error.WriteLine("  procgen-cli mix-seed-table");
    Console.Error.WriteLine("  procgen-cli room-kit-specs");
}
