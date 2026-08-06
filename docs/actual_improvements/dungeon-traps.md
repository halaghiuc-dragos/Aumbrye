# Dungeon traps — improvement plan

## Status: FINISHED

## Current state

Spike and falling traps are telegraphed, route damage through `TrapDamageArea` → `Hurtbox.receive_hit`, and honor inspector `@export` damage on the controller. `trigger_radius` is raised to at least the `DamageArea` horizontal half-extent plus 0.5 m. Room `trap_spike_pack` adds entry `x`/`y`/`z` offsets on top of `PropAnchor_0`. `TrapCatalog` resolves five trap ids (`spike_trap`, `falling_trap`, `poison_pool`, `frost_trap`, `shadow_trap`) to scenes under `content/traps/*.json`. Falling traps restore the block to the ceiling before re-arming IDLE. Legacy `SpikesMesh` is removed from spike and shadow trap scenes. See [`../existing_codebase/dungeon-traps.md`](../existing_codebase/dungeon-traps.md).

## Gaps

| ID | Sev | Gap | Evidence | Resolution |
|----|-----|-----|----------|------------|
| TRP-01 | P1 | `@export damage` / `poise_damage` on trap scripts unused — only tscn child values apply | `spike_trap.gd:9-10`; `falling_trap.gd:9-10` | **Done** — `_ready` copies exports onto `$DamageArea` (`spike_trap.gd:31-32`; `falling_trap.gd:33-34`) |
| TRP-02 | P1 | Triggers use player body position, not hurtbox — can telegraph/fire without a valid hit volume overlap | `spike_trap.gd:43`; `falling_trap.gd:42` | **Done** — `_sync_trigger_radius_from_hitbox()` ensures `trigger_radius >= damage half-extent + 0.5` (`spike_trap.gd:76-91`; `falling_trap.gd:72-87`) |
| TRP-03 | P1 | `room_trap_content` ignores `entry` — fixed offset `(0, 0, 2)` only | `room_trap_content.gd:6-9` | **Done** — `configure` adds entry offset to anchor (`room_trap_content.gd:7-13`) |
| TRP-04 | P2 | `trap_damage_area` `area_entered`-only — standing in zone when monitoring enables may miss first hit | `trap_damage_area.gd:15-33` | **Done** — `set_damage_active(true)` calls `scan_overlapping_areas()` (`trap_damage_area.gd:22-46`) |
| TRP-05 | P2 | `frost_trap` / `shadow_trap` ids have no distinct scenes | `dungeon_builder.gd:679-684` | **Done** — `TrapCatalog` + `content/traps/frost_trap.json`, `shadow_trap.json`, and matching `.tscn` files |
| TRP-06 | P2 | Falling trap RESET waits 2s at floor with no re-telegraph | `falling_trap.gd:56-63` | **Done** — block snaps to `_rest_y` on RESET entry; IDLE only after cooldown (`falling_trap.gd:60-69`) |
| TRP-07 | P2 | Legacy `SpikesMesh` kept hidden beside runtime diorama spikes | `spike_trap.tscn`; `shadow_trap.tscn` | **Done** — node removed; `_ready` builds diorama only (`spike_trap.gd:27-28`) |

## Target design

### Single damage authority (TRP-01)

Trap `_ready` copies exports onto `$DamageArea`:

```gdscript
_hitbox.damage = damage
_hitbox.poise_damage = poise_damage
```

Designers tune the script (or a future JSON trap def); scene defaults remain fallbacks. Same forwarding as HAZ-05.

### Trigger volume (TRP-02)

Chosen: keep proximity trigger for telegraph readability, but size `trigger_radius` from the damage shape (e.g. max horizontal extent of `DamageArea` shape + margin) so telegraph implies the hit volume. Rejected: hurtbox-only trigger — players would stand on the plate without telegraph if only the capsule edge grazes.

Document the rule: telegraph radius >= damage footprint.

### Authored room offsets (TRP-03)

```gdscript
trap.position = _anchor(0).position + Vector3(
    float(entry.get("x", 0.0)),
    float(entry.get("y", 0.0)),
    float(entry.get("z", 2.0))
)
```

Procgen entries that omit coords keep anchor position with default `z` offset 2.

### ACTIVE admission scan (TRP-04)

Share the helper from HAZ-06: when monitoring flips true, scan overlapping areas once.

### Honest ids (TRP-05)

`TrapCatalog.get_scene_path` loads `content/traps/<id>.json` and returns the `scene` path. Biome `trapPool` entries reference real ids; builder logs an error when a path is missing (`dungeon_builder.gd:679-684`).

### Falling re-arm (TRP-06)

RESET → brief TELEGRAPH (0.5× first telegraph) → IDLE, or go IDLE only after block returns to ceiling so the next proximity trigger always shows a full telegraph. Chosen: return to IDLE only after ceiling restore so the existing TELEGRAPH state always runs.

### Scene cleanup (TRP-07)

Remove legacy `SpikesMesh` from spike/shadow trap scenes once diorama path is mandatory (it already is in `_ready`).

## Work plan

1. **Forward damage exports in spike + falling `_ready`** — trap scripts. Closes TRP-01. **Done**
2. **Derive or document trigger radius vs damage shape; adjust defaults** — trap scripts + scenes. Closes TRP-02. **Done**
3. **Honor `entry` position in `room_trap_content`** — `room_trap_content.gd`. Closes TRP-03. **Done**
4. **ACTIVE overlap scan** — with HAZ-06 on `trap_damage_area`. Closes TRP-04. **Done**
5. **Add frost/shadow scenes + TrapCatalog entries** (or remove fake ids). Closes TRP-05. **Done**
6. **Falling trap ceiling restore before IDLE** — `falling_trap.gd`. Closes TRP-06. **Done**
7. **Delete legacy SpikesMesh from tscn** — `spike_trap.tscn`, `shadow_trap.tscn`. Closes TRP-07. **Done**

## Data and schema changes

Trap definitions live in `content/traps/*.json` with `id` and `scene` keys, resolved by `TrapCatalog`. No save migrator.

## Acceptance criteria

- [x] Changing `spike_trap.damage` in the inspector changes dealt HP (child area matches). (TRP-01) — `spike_trap.gd:31-32`; `trap_suite.gd` `trp.damage.export_forward`
- [x] Telegraph radius fully covers the DamageArea horizontal footprint for default scenes. (TRP-02) — `_sync_trigger_radius_from_hitbox()` in both trap scripts
- [x] Room content entry `{ "x": 3 }` places the spike at local x=3. (TRP-03) — `room_trap_content.gd:8-12`; `trap_suite.gd` `trp.room_content.offset`
- [x] Player standing in spikes when ACTIVE begins takes damage without leaving and re-entering. (TRP-04) — `trap_damage_area.gd:22-46`; `trap_suite.gd` `trp.active.scan_hit`
- [x] Generated swamp/frost/shadow corridor traps resolve to an existing `.tscn` whose id matches the table name, or the table no longer emits alias ids. (TRP-05) — `TrapCatalog`; `trap_suite.gd` `trp.builder.ids_resolve`
- [x] Second proximity trigger on a falling trap shows a telegraph before the block falls. (TRP-06) — `falling_trap.gd:60-69` (ceiling restore before IDLE re-arm)

## Validation

| Assertion id | Checks | Status |
|--------------|--------|--------|
| `trp.damage.export_forward` | Set script damage 30, assert child area damage 30 after `_ready` | IMPLEMENTED — `trap_suite.gd` |
| `trp.room_content.offset` | Spawn with entry z=5, assert local origin z≈5 | IMPLEMENTED — `trap_suite.gd` |
| `trp.active.scan_hit` | Overlap before enable, enable+scan, assert HP drop | IMPLEMENTED — `trap_suite.gd` |
| `trp.builder.ids_resolve` | Every `TrapCatalog` id resolves to an existing scene | IMPLEMENTED — `trap_suite.gd` |

## Related

- Existing state: [`../existing_codebase/dungeon-traps.md`](../existing_codebase/dungeon-traps.md)
- [`combat-hazards.md`](combat-hazards.md), [`dungeon-builder.md`](dungeon-builder.md), [`procgen-placements.md`](procgen-placements.md)
