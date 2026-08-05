using System.Text.Json;
using System.Text.Json.Nodes;
using Aumbrye.Procedural.Biome;
using Aumbrye.Procedural.Content;
using Aumbrye.Procedural.Generation;
using Xunit;

namespace Aumbrye.UnitTests;

public class ContentCatalogTests
{
    [Fact]
    public void EnemyCatalog_LoadsAllCastleEnemiesAndBoss()
    {
        foreach (var enemyId in new[]
                 {
                     "castle_grunt", "castle_archer", "castle_shield",
                     "boss_castle_knight", "training_grunt",
                 })
        {
            Assert.True(EnemyCatalog.TryGet(enemyId, out var def));
            Assert.NotNull(def);
            Assert.False(string.IsNullOrWhiteSpace(def!.ContentPath));
        }
    }

    [Fact]
    public void ItemCatalog_LoadsAllCatalogItems()
    {
        foreach (var itemId in new[]
                 {
                     "castle_sword", "health_potion", "iron_scrap", "knight_relic",
                 })
        {
            Assert.True(ItemCatalog.TryGet(itemId, out var def));
            Assert.NotNull(def);
            Assert.True(def!.LootValue > 0);
            Assert.Contains("items/", def.ContentPath);
        }
    }

    [Fact]
    public void ItemCatalog_UsesLootValueWhenPresent()
    {
        Assert.Equal(5, ItemCatalog.GetLootValue("health_potion"));
        Assert.Equal(3, ItemCatalog.GetLootValue("iron_scrap"));
    }

    [Fact]
    public void BiomeEnemyPool_ReferencesKnownEnemies()
    {
        var biome = BiomeCatalog.GetRequired("forgotten_castle");
        Assert.NotEmpty(biome.EnemyPool);
        foreach (var entry in biome.EnemyPool)
            Assert.True(EnemyCatalog.TryGet(entry.EnemyId, out _));
        foreach (var boss in biome.BossPool)
            Assert.True(EnemyCatalog.TryGet(boss.EnemyId, out _));
    }

    [Fact]
    public void GeneratedEnemies_AreFromBiomePool()
    {
        var biome = BiomeCatalog.GetRequired("forgotten_castle");
        var allowed = biome.EnemyPool.Select(e => e.EnemyId)
            .Concat(biome.BossPool.Select(b => b.EnemyId))
            .ToHashSet(StringComparer.Ordinal);

        var result = DungeonGenerator.Generate("forgotten_castle", 55_555, 1, 1, Guid.NewGuid());
        Assert.Equal("boss_castle_knight", result.Definition.Placements.Boss!.EnemyId);
        foreach (var enemy in result.Definition.Placements.Enemies)
            Assert.Contains(enemy.EnemyId, allowed);
    }

    [Fact]
    public void GeneratedLoot_UsesKnownItemIds()
    {
        var result = DungeonGenerator.Generate("forgotten_castle", 77_777, 1, 1, Guid.NewGuid());
        foreach (var chest in result.Definition.Placements.Loot)
        foreach (var item in chest.Items)
            Assert.True(ItemCatalog.TryGet(item.ItemId, out _));
    }
}
