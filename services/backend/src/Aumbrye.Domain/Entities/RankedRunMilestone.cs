namespace Aumbrye.Domain.Entities;

/// <summary>
/// Events emitted by the authoritative run host. These are intentionally separate from the
/// client completion payload: a player can report an outcome, but only the game authority can
/// observe an encounter and attest that it was completed.
/// </summary>
public enum RankedRunMilestoneKind
{
    EncounterStarted = 0,
    BossDefeated = 1,
    FinalObjectiveCompleted = 2,
    Escaped = 3,
}

public sealed class RankedRunMilestone
{
    public Guid Id { get; set; }
    public Guid RunId { get; set; }
    public Run Run { get; set; } = null!;
    public Guid AccountId { get; set; }
    public int Sequence { get; set; }
    public RankedRunMilestoneKind Kind { get; set; }
    public DateTimeOffset ObservedAt { get; set; }
    /// <summary>Stable identity of the trusted session host that emitted this observation.</summary>
    public string AuthorityId { get; set; } = string.Empty;
}
