# M6 item generation — run from repo root
$ErrorActionPreference = "Stop"
Set-Location (Split-Path (Split-Path $PSScriptRoot))

function Write-Item($id, $slot, $rarity, $stats, $theme = "") {
    $type = switch ($slot) {
        "consumable" { "consumable" }
        "relic" { "relic" }
        "weapon" { "weapon" }
        default { "armor" }
    }
    $equipSlot = if ($slot -in @("helmet","chest","gloves","boots","ring","amulet","weapon","relic")) { $slot } else { $null }
    $obj = [ordered]@{
        id = $id
        name = (Get-Culture).TextInfo.ToTitleCase(($id -replace '_', ' '))
        itemType = $type
        gridWidth = 2
        gridHeight = 2
        stackSize = if ($slot -eq "consumable") { 10 } else { 1 }
        rarity = $rarity
        description = ""
        value = $null
        authored = $false
        stats = $stats
    }
    if ($equipSlot) { $obj.equipmentSlot = $equipSlot }
    if ($theme) { $obj.theme = $theme }
    $dir = switch ($slot) {
        "consumable" { "content/items/consumables" }
        "relic" { "content/relics" }
        default { "content/items/equipment" }
    }
    ($obj | ConvertTo-Json -Depth 5) | Set-Content "$dir/$id.json" -Encoding UTF8
}

# Theme uniques
Write-Item "frost_ice_ring" "ring" "rare" @{ frostDamage = 8; maxHealth = 10 } "frozen_fortress"
Write-Item "frost_warlord_blade" "weapon" "legendary" @{ physicalDamage = 28; frostDamage = 12 } "frozen_fortress"
Write-Item "frost_raider_boots" "boots" "rare" @{ defense = 5; moveSpeed = 0.1 } "frozen_fortress"
Write-Item "frost_glacier_sword" "weapon" "epic" @{ physicalDamage = 22; frostDamage = 8 } "frozen_fortress"
Write-Item "frost_knight_helm" "helmet" "rare" @{ defense = 8; maxHealth = 15 } "frozen_fortress"
Write-Item "frost_knight_plate" "chest" "epic" @{ defense = 14; maxHealth = 25 } "frozen_fortress"
Write-Item "frost_gauntlets" "gloves" "rare" @{ defense = 4; attackSpeed = 0.05 } "frozen_fortress"
Write-Item "frost_amulet" "amulet" "rare" @{ frostDamage = 6; staminaRegen = 2 } "frozen_fortress"
Write-Item "cathedral_holy_charm" "amulet" "rare" @{ arcaneDamage = 8; maxHealth = 12 } "dark_cathedral"
Write-Item "cathedral_shadow_dagger" "weapon" "legendary" @{ physicalDamage = 20; arcaneDamage = 14 } "dark_cathedral"
Write-Item "cathedral_warden_helm" "helmet" "rare" @{ defense = 7; maxHealth = 12 } "dark_cathedral"
Write-Item "cathedral_arcane_staff" "weapon" "epic" @{ arcaneDamage = 24 } "dark_cathedral"
Write-Item "cathedral_shadow_cloak" "chest" "epic" @{ defense = 10; evasion = 0.05 } "dark_cathedral"
Write-Item "cathedral_sanctum_ring" "ring" "rare" @{ arcaneDamage = 6; defense = 3 } "dark_cathedral"
Write-Item "cathedral_pilgrim_boots" "boots" "common" @{ defense = 3; moveSpeed = 0.05 } "dark_cathedral"
Write-Item "cathedral_gloves" "gloves" "common" @{ defense = 3; attackSpeed = 0.03 } "dark_cathedral"

# Generic fill
$fill = @(
    @("iron_helm","helmet","common",@{defense=3}),
    @("iron_plate","chest","common",@{defense=5}),
    @("iron_gauntlets","gloves","common",@{defense=2}),
    @("iron_boots","boots","common",@{defense=2}),
    @("copper_ring","ring","common",@{maxHealth=5}),
    @("silver_ring","ring","magic",@{maxHealth=10;staminaRegen=1}),
    @("gold_ring","ring","rare",@{maxHealth=15;physicalDamage=3}),
    @("jade_amulet","amulet","magic",@{defense=3;maxHealth=8}),
    @("ruby_amulet","amulet","rare",@{physicalDamage=5;maxHealth=12}),
    @("steel_helm","helmet","magic",@{defense=5;maxHealth=8}),
    @("steel_plate","chest","magic",@{defense=8;maxHealth=12}),
    @("steel_gauntlets","gloves","magic",@{defense=4;attackSpeed=0.02}),
    @("steel_boots","boots","magic",@{defense=4;moveSpeed=0.03}),
    @("knight_blade","weapon","rare",@{physicalDamage=18}),
    @("iron_sword","weapon","common",@{physicalDamage=10}),
    @("flame_sword","weapon","epic",@{physicalDamage=20;fireDamage=8}),
    @("venom_dagger","weapon","rare",@{physicalDamage=14;poisonDamage=6}),
    @("crystal_bow","weapon","rare",@{physicalDamage=16;attackSpeed=0.08}),
    @("war_hammer","weapon","epic",@{physicalDamage=26}),
    @("sage_staff","weapon","rare",@{arcaneDamage=18}),
    @("relic_bloodstone","relic","rare",@{lifesteal=0.03}),
    @("relic_wind_charm","relic","rare",@{moveSpeed=0.08}),
    @("relic_stone_heart","relic","epic",@{maxHealth=40;defense=5}),
    @("relic_flame_core","relic","epic",@{fireDamage=10}),
    @("relic_frost_shard","relic","epic",@{frostDamage=10}),
    @("relic_shadow_veil","relic","legendary",@{evasion=0.1;arcaneDamage=8}),
    @("relic_sun_medallion","relic","legendary",@{maxHealth=30;staminaRegen=4}),
    @("relic_poison_vial","relic","rare",@{poisonDamage=8}),
    @("mana_potion","consumable","common",@{}),
    @("stamina_potion","consumable","common",@{}),
    @("antidote","consumable","common",@{}),
    @("elixir_vigor","consumable","rare",@{}),
    @("elixir_might","consumable","rare",@{}),
    @("scroll_teleport","consumable","magic",@{}),
    @("scroll_identify","consumable","common",@{}),
    @("bomb_fire","consumable","magic",@{}),
    @("bomb_frost","consumable","magic",@{}),
    @("rations","consumable","common",@{}),
    @("herb_healing","consumable","common",@{}),
    @("leather_helm","helmet","common",@{defense=2}),
    @("leather_vest","chest","common",@{defense=3}),
    @("leather_gloves","gloves","common",@{defense=1}),
    @("leather_boots","boots","common",@{defense=2;moveSpeed=0.02}),
    @("mythic_crown","helmet","mythic",@{defense=12;maxHealth=50}),
    @("mythic_aegis","chest","mythic",@{defense=20;maxHealth=60}),
    @("mythic_blade","weapon","mythic",@{physicalDamage=35;attackSpeed=0.1}),
    @("mythic_ring","ring","mythic",@{physicalDamage=10;arcaneDamage=10;maxHealth=25}),
    @("ember_gauntlets","gloves","epic",@{fireDamage=6;defense=5}),
    @("tide_boots","boots","epic",@{defense=5;moveSpeed=0.1}),
    @("void_amulet","amulet","legendary",@{arcaneDamage=12;maxHealth=20}),
    @("thorn_ring","ring","magic",@{physicalDamage=4;defense=2}),
    @("scout_bow","weapon","magic",@{physicalDamage=12;attackSpeed=0.05}),
    @("guard_shield","chest","rare",@{defense=12}),
    @("pilgrim_staff","weapon","common",@{arcaneDamage=8})
)
foreach ($row in $fill) { Write-Item $row[0] $row[1] $row[2] $row[3] }

Write-Host "M6 items generated"
