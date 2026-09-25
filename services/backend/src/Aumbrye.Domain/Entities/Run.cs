namespace Aumbrye.Domain.Entities;

public enum RunStatus
{
    Active = 0,
    Completed = 1,
    Abandoned = 2,
}

public class Run
{
    /// <summary>Hard ceiling on the floor index any single run may generate or complete on.</summary>
    public const int MaxFloorsPerRun = 100;

    /// <summary>
    /// How far ahead of the highest floor the run has reached a client may pre-generate. Bounds
    /// the CPU and cache a single authenticated caller can burn by walking the floor parameter.
    /// </summary>
    public const int FloorLookaheadLimit = 3;

    public Guid Id { get; set; }
    public Guid AccountId { get; set; }
    public Account Account { get; set; } = null!;
    public string BiomeId { get; set; } = string.Empty;
    public int Seed { get; set; }
    public int Tier { get; set; }
    public int PlayerLevelSnapshot { get; set; }
    public string ClientVersionSnapshot { get; set; } = "legacy-unknown";
    public RunStatus Status { get; set; } = RunStatus.Active;
    public string? Outcome { get; set; }
    public string Mode { get; set; } = "dungeon";
    public bool FinalObjectiveCompleted { get; set; }
    public int Assists { get; set; }
    public string Ruleset { get; set; } = "standard-v1";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public string? DefinitionChecksum { get; set; }
    public bool RankedDefinitionEligible { get; set; }
    /// <summary>True only when run progression was attested by a trusted server authority.</summary>
    public bool RankedProgressionVerified { get; set; }

    /// <summary>
    /// Union of every loot instance the run has generated, across all floors, serialized as
    /// <c>{ instanceId: { itemId, quantity, floor } }</c>. Floors merge into this map the first
    /// time they are generated, so a claim made on floor 1 still validates when the player
    /// completes on floor 7.
    /// </summary>
    public string? LootInstanceIdsJson { get; set; }

    /// <summary>Highest floor index this run has generated. Gates how far ahead a client may reach.</summary>
    public int HighestFloorGenerated { get; set; } = 1;

    /// <summary>
    /// Client-reported run duration, validated against the server wall clock at completion. This
    /// is the ranked metric — it excludes pause and menu time, which the wall-clock window cannot.
    /// </summary>
    public double? ElapsedSeconds { get; set; }

    /// <summary>Set once the run has been pushed to a leaderboard, making submission idempotent.</summary>
    public DateTimeOffset? LeaderboardSubmittedAt { get; set; }

    /// <summary>
    /// Cached completion payload, replayed verbatim when a client retries <c>/complete</c> after a
    /// timeout so a duplicate POST is a no-op rather than a second progression grant.
    /// </summary>
    public string? CompletionResultJson { get; set; }
}
