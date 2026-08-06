using Aumbrye.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

#nullable disable

namespace Aumbrye.Infrastructure.Persistence.Migrations;

[DbContext(typeof(AumbryeDbContext))]
partial class AumbryeDbContextModelSnapshot : ModelSnapshot
{
    protected override void BuildModel(ModelBuilder modelBuilder)
    {
#pragma warning disable 612, 618
        modelBuilder
            .HasAnnotation("ProductVersion", "8.0.11")
            .HasAnnotation("Relational:MaxIdentifierLength", 63);

        modelBuilder.Entity<Account>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.DisplayName).IsUnique();
            entity.HasIndex(e => e.Email).IsUnique();
            entity.Property(e => e.DisplayName).HasMaxLength(32);
            entity.Property(e => e.Email).HasMaxLength(256);
            entity.Property(e => e.PasswordHash).HasMaxLength(512);
            entity.HasOne(e => e.SaveBlob).WithOne(e => e.Account).HasForeignKey<SaveBlob>(e => e.AccountId);
        });

        modelBuilder.Entity<RefreshToken>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.TokenHash);
            entity.Property(e => e.ReplacedByTokenHash).HasMaxLength(128);
            entity.Property(e => e.TokenHash).HasMaxLength(128);
        });

        modelBuilder.Entity<Run>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.AccountId, e.Status });
            entity.Property(e => e.BiomeId).HasMaxLength(64);
            entity.Property(e => e.DefinitionChecksum).HasMaxLength(128);
            entity.Property(e => e.LootInstanceIdsJson).HasColumnType("jsonb");
        });

        modelBuilder.Entity<SaveBlob>(entity =>
        {
            entity.HasKey(e => e.AccountId);
            entity.Property(e => e.JsonData).HasColumnType("jsonb");
        });
#pragma warning restore 612, 618
    }
}
