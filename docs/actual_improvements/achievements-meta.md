# Achievements and meta — improvement plan

## Current state
`AchievementService` can unlock, toast, persist, and optionally call Steam. See [`../existing_codebase/achievements-meta.md`](../existing_codebase/achievements-meta.md). Only the escape-meta path in `RunFlow._handle_escape_meta` awards achievements. Nineteen catalog entries describe player actions that never call `unlock`. Steam sync on load is unused; stub mode is the default development path. `mythic_loot` still names a rarity the client renamed to `aumbral`.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| ACH-01 | P0 | 19 catalog achievements have zero unlock call sites (`first_blood`, loot tiers, equip, talents, hub counters, combat counters, `no_damage_boss`, `arena_victor`, …) | `catalog.json:4-29` vs grep of `AchievementService.unlock` — only `run_flow.gd:762-774` |
| ACH-02 | P0 | Catalog presents `mythic_loot` while runtime rarity is `aumbral` (`RarityRegistry.LEGACY_ALIASES`); even a future unlock would mismatch player-facing rarity names | `catalog.json:16`, `rarity_registry.gd:10-12` |
| ACH-03 | P1 | `SteamService.sync_achievements` never runs after `_load_from_save`, so Steam does not receive previously earned local unlocks | `achievement_service.gd:24-28`, `steam_service.gd:91-98` |
| ACH-04 | P1 | Leaderboard submit unlock requires API `ok`; offline opt-in players never earn `leaderboard_submit` and get no local feedback that submit failed | `run_flow.gd:769-774` |
| ACH-05 | P2 | No achievements UI beyond the toast; players cannot see locked/unlocked progress | Toast-only at `achievement_service.gd:110-114` |

## Target design

### Event-driven unlock registry
Stop scattering string literals. Add a thin dispatcher on `AchievementService`:

```gdscript
func notify(event: String, context: Dictionary = {}) -> void
```

Map catalog ids to event predicates in data (extend `catalog.json` or a sibling `hooks.json`):

| Event | Achievement ids |
|-------|-----------------|
| `enemy_killed` first time | `first_blood` |
| `item_obtained` with rarity | `epic_loot` / `legendary_loot` / `aumbral_loot` (rename) |
| `equipment_full` | `full_equip` |
| `talent_points_spent` ≥ 10 | `talent_spender` |
| `merchant_buy` count | `merchant_friend` |
| `blacksmith_craft` count | `blacksmith_patron` |
| `quest_completed` count | `quest_complete` |
| `parry` / `dodge` / `status_applied` counters | combat masteries |
| `boss_defeated_no_damage` | `no_damage_boss` |
| `arena_won` | `arena_victor` |

Counters live in `CharacterService` flags (or meta) so they survive runs. Rejected alternative: keep one-off `unlock("…")` calls at every site — that is how the current dead catalog happened.

### Steam honesty
On `_load_from_save`, if `SteamService.is_available()` and not stub, call `SteamService.sync_achievements(get_unlocked_ids())`. Document stub mode in Settings as "Steam unavailable (dev stub)" rather than silently succeeding.

### Rarity rename
Replace `mythic_loot` id with `aumbral_loot` in catalog + any saves: migrator maps old key if present. Description uses "aumbral rarity item".

### Leaderboard
Unlock `leaderboard_submit` when the client **attempts** a submit while opted in and the run qualifies, or show a results-screen line when `ok` is false. Prefer attempt-based unlock only if product wants offline credit; otherwise keep success-gated unlock but surface the failure.

## Work plan

1. **Audit catalog vs call sites** — table in validation that every `achievements[].id` appears in a `notify` map or an allowlist of intentionally manual unlocks. Closes discovery for ACH-01.
2. **Add `notify` + counter flags + wire first_blood / loot rarities / full_equip / talent_spender** — highest-visibility P0 set. Closes ACH-01 for those ids; rename mythic→aumbral (ACH-02).
3. **Wire hub and combat counters** — merchant, blacksmith, quests, parry, dodge, statuses, freeze/poison, arena, no-damage boss. Remaining ACH-01.
4. **Steam sync on load + Settings stub label** — Closes ACH-03.
5. **Leaderboard failure feedback + optional unlock policy** — Closes ACH-04.
6. **Simple achievements panel in pause/settings** — list from catalog with unlocked state. Closes ACH-05.

## Data and schema changes

- `content/schemas/achievement-catalog.v1.json`: allow optional `event` / `threshold` fields, or add `content/achievements/hooks.json` with its own schema.
- Rename `mythic_loot` → `aumbral_loot` in `catalog.json`.
- Save: `meta.achievements` key rename via `save_migrator.gd` bump (map old id if true). Document in `docs/SAVE_MIGRATIONS.md`.

## Acceptance criteria
- [ ] Every id in `catalog.json` has either a `notify` predicate or an explicit `manualUnlock: true` reviewed entry; CI fails otherwise. (ACH-01)
- [ ] Obtaining an `aumbral` rarity instance unlocks `aumbral_loot`; `mythic_loot` is absent from catalog. (ACH-02)
- [ ] With Steam non-stub, loading a save that already has `boss_slayer` calls `sync_achievements` with that id. (ACH-03)
- [ ] Failed leaderboard submit shows a results or hub message when opted in. (ACH-04)
- [ ] Pause or settings lists all non-hidden achievements with locked/unlocked state. (ACH-05)

## Validation
Extend `m6_suite.gd` / new `achievements_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `ach.catalog.every_id_has_hook` | Each catalog id ∈ notify map or manual allowlist |
| `ach.unlock.first_blood` | Simulate one kill event → `is_unlocked("first_blood")` |
| `ach.unlock.aumbral_loot` | Notify item rarity aumbral → unlocked |
| `ach.steam.sync_on_load` | After seeding unlocks, `_load_from_save` path invokes sync (mock) |

## Related
- Existing state: [`../existing_codebase/achievements-meta.md`](../existing_codebase/achievements-meta.md)
- [`run-flow.md`](run-flow.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`platform-and-net.md`](platform-and-net.md)
