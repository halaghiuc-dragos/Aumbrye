namespace Aumbrye.ProcgenCli;

public static class ProcgenCliArgs
{
    public static GenerateOptions ParseGenerateArgs(string[] args)
    {
        if (args.Length < 3)
            throw new ArgumentException("Usage: procgen-cli generate <biomeId> <seed> [runId] [--tier N] [--player-level N]");

        var biomeId = args[1];
        if (!int.TryParse(args[2], out var seed) || seed < 1)
            throw new ArgumentException("Seed must be a positive integer.");

        var runId = Guid.NewGuid();
        var tier = 1;
        var playerLevel = 1;
        var floorIndex = 1;
        var isFinalFloor = false;
        var index = 3;

        if (index < args.Length && Guid.TryParse(args[index], out var parsedRunId))
        {
            runId = parsedRunId;
            index++;
        }

        while (index < args.Length)
        {
            switch (args[index])
            {
                case "--floor" when index + 1 < args.Length && int.TryParse(args[index + 1], out var parsedFloor):
                    floorIndex = Math.Max(1, parsedFloor);
                    index += 2;
                    break;
                case "--final-floor":
                    isFinalFloor = true;
                    index += 1;
                    break;
                case "--tier" when index + 1 < args.Length && int.TryParse(args[index + 1], out var parsedTier):
                    tier = Math.Max(1, parsedTier);
                    index += 2;
                    break;
                case "--player-level" when index + 1 < args.Length && int.TryParse(args[index + 1], out var parsedLevel):
                    playerLevel = Math.Max(1, parsedLevel);
                    index += 2;
                    break;
                default:
                    throw new ArgumentException($"Unknown argument: {args[index]}");
            }
        }

        return new GenerateOptions(biomeId, seed, runId, tier, playerLevel, floorIndex, isFinalFloor);
    }
}

public sealed record GenerateOptions(
    string BiomeId,
    int Seed,
    Guid RunId,
    int Tier,
    int PlayerLevel,
    int FloorIndex,
    bool IsFinalFloor);
