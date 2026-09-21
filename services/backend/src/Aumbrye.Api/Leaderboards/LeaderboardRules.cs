using Aumbrye.Shared.Contracts.Leaderboards;

namespace Aumbrye.Api.Leaderboards;

public static class LeaderboardRules
{
    public const string Version = "2026.09.15";
    public const int MinimumTier = 1;
    public const int MaximumTier = 10;

    public static readonly IReadOnlyList<LeaderboardBiomeOption> Biomes =
    [
        new("forgotten_castle", "Forgotten Castle"),
        new("crystal_caverns", "Crystal Caverns"),
        new("poison_swamp", "Poison Swamp"),
        new("frozen_fortress", "Frozen Fortress"),
        new("dark_cathedral", "Dark Cathedral"),
        new("glacial_hollow", "Glacial Hollow"),
        new("iron_vault", "Iron Vault"),
        new("prism_depths", "Prism Depths"),
        new("umbral_chapel", "Umbral Chapel"),
        new("venom_mire", "Venom Mire")
    ];

    public static LeaderboardCapabilitiesResponse Capabilities { get; } =
        new(Version, MinimumTier, MaximumTier, Biomes);
}
