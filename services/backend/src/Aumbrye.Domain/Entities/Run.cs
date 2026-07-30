namespace Aumbrye.Domain.Entities;

public enum RunStatus
{
    Active = 0,
    Completed = 1,
    Abandoned = 2,
}

public class Run
{
    public Guid Id { get; set; }
    public Guid AccountId { get; set; }
    public Account Account { get; set; } = null!;
    public string BiomeId { get; set; } = string.Empty;
    public int Seed { get; set; }
    public int Tier { get; set; }
    public int PlayerLevelSnapshot { get; set; }
    public RunStatus Status { get; set; } = RunStatus.Active;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public string? DefinitionChecksum { get; set; }
}
