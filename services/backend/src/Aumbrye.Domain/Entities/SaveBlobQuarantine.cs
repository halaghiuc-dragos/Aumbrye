namespace Aumbrye.Domain.Entities;

/// <summary>
/// A save blob the server could not parse, preserved verbatim.
/// </summary>
/// <remarks>
/// Replacing an unreadable save with a fresh default character silently destroys a player's
/// progress and the next PUT persists that default over whatever was recoverable. Quarantining
/// the raw JSON instead keeps the forensic data and lets support restore by hand.
/// </remarks>
public class SaveBlobQuarantine
{
    public Guid Id { get; set; }
    public Guid AccountId { get; set; }
    public DateTimeOffset CapturedAt { get; set; }
    public string RawJson { get; set; } = string.Empty;
    public string? Reason { get; set; }
}
