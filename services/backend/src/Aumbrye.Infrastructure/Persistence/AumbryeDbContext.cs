using Aumbrye.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace Aumbrye.Infrastructure.Persistence;

public class AumbryeDbContext : DbContext
{
    public AumbryeDbContext(DbContextOptions<AumbryeDbContext> options) : base(options) { }

    public DbSet<Account> Accounts => Set<Account>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<Run> Runs => Set<Run>();
    public DbSet<SaveBlob> SaveBlobs => Set<SaveBlob>();
    public DbSet<SaveBlobQuarantine> SaveBlobQuarantines => Set<SaveBlobQuarantine>();

    /// <summary>
    /// SteamID64 values are unsigned, but Postgres has no unsigned 64-bit type and Npgsql refuses
    /// to map <c>ulong</c> to <c>bigint</c> on its own. An unchecked bit-cast round-trips every
    /// possible SteamID64 exactly, including the (currently unreachable) range above long.MaxValue.
    /// </summary>
    private static readonly ValueConverter<ulong?, long?> SteamIdConverter = new(
        v => v.HasValue ? unchecked((long)v.Value) : null,
        v => v.HasValue ? unchecked((ulong)v.Value) : null);

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Account>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Email).IsUnique().HasFilter("\"Email\" IS NOT NULL");
            e.HasIndex(x => x.DisplayName).IsUnique();
            e.HasIndex(x => x.SteamId).IsUnique().HasFilter("\"SteamId\" IS NOT NULL");
            e.Property(x => x.Email).HasMaxLength(256);
            e.Property(x => x.DisplayName).HasMaxLength(32);
            e.Property(x => x.PasswordHash).HasMaxLength(512);
            e.Property(x => x.SteamId).HasConversion(SteamIdConverter).HasColumnType("bigint");
            e.HasOne(x => x.SaveBlob).WithOne(x => x.Account).HasForeignKey<SaveBlob>(x => x.AccountId);
        });

        modelBuilder.Entity<RefreshToken>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.TokenHash);
            // Keeps the hourly set-based cleanup DELETE cheap as the table grows.
            e.HasIndex(x => x.ExpiresAt);
            e.HasIndex(x => x.RevokedAt);
            e.Property(x => x.TokenHash).HasMaxLength(128);
            e.Property(x => x.ReplacedByTokenHash).HasMaxLength(128);
        });

        modelBuilder.Entity<Run>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.AccountId, x.Status });
            e.Property(x => x.BiomeId).HasMaxLength(64);
            e.Property(x => x.DefinitionChecksum).HasMaxLength(128);
        });

        modelBuilder.Entity<SaveBlob>(e =>
        {
            e.HasKey(x => x.AccountId);
        });

        modelBuilder.Entity<SaveBlobQuarantine>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => new { x.AccountId, x.CapturedAt });
        });
    }
}
