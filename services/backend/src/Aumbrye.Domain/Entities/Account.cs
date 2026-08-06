namespace Aumbrye.Domain.Entities;

public class Account
{
    public Guid Id { get; set; }
    public string? Email { get; set; }
    public string DisplayName { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public ulong? SteamId { get; set; }
    public DateTimeOffset? SteamLinkedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public ICollection<RefreshToken> RefreshTokens { get; set; } = new List<RefreshToken>();
    public ICollection<Run> Runs { get; set; } = new List<Run>();
    public SaveBlob? SaveBlob { get; set; }
}
