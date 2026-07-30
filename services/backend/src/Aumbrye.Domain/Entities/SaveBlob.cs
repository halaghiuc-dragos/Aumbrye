namespace Aumbrye.Domain.Entities;

public class SaveBlob
{
    public Guid AccountId { get; set; }
    public Account Account { get; set; } = null!;
    public string JsonData { get; set; } = "{}";
    public DateTimeOffset UpdatedAt { get; set; }
}
