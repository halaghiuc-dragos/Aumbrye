# Dungeon traps — improvement plan

## Current state

Spike and falling traps are playable, telegraphed, and honest about Hurtbox admission (i-frames work). Controller `@export` damage fields are dead; only scene child values apply. Triggers use body proximity, which can fire when the hurtbox never overlaps the damage volume. Procgen emits `frost_trap` / `shadow_trap` ids that silently alias to poison / spike. Room content always drops one spike at a fixed local offset. See [`../existing_codebase/dungeon-traps.md`](../existing_codebase/dungeon-traps.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| TRP-01 | P1 | `@export damage` / `poise_damage` on trap scripts unused — only tscn child values apply | `spike_trap.gd:9-10`; `falling_trap.gd:9-10`; matching `.tscn` |
| TRP-02 | P1 | Triggers use player body position, not hurtbox — can telegraph/fire without a valid hit volume overlap | `spike_trap.gd:43`; `falling_trap.gd:42` |
| TRP-03 | P1 | `room_trap_content` ignores `entry` — fixed offset `(0, 0, 2)` only | `room_trap_content.gd:6-9` |
| TRP-04 | P2 | `trap_damage_area` `area_entered`-only — standing in zone when monitoring enables may miss first hit | `trap_damage_area.gd:15-33` |
| TRP-05 | P2 | `frost_trap` / `shadow_trap` ids have no distinct scenes | `dungeon_builder.gd:507-510` |
| TRP-06 | P2 | Falling trap RESET waits 2s at floor with no re-telegraph | `falling_trap.gd:56-63` |
| TRP-07 | P2 | Legacy `SpikesMesh` kept hidden beside runtime diorama spikes | `spike_trap.gd:27-31`; `spike_trap.tscn` |

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
func spawn(parent: Node3D, entry: Dictionary) -> void:
    var local := Vector3(
        float(entry.get("x", 0.0)),
        float(entry.get("y", 0.0)),
        float(entry.get("z", 2.0))
    )
    ...
```

Procgen entries that omit coords keep `(0,0,2)` as default.

### ACTIVE admission scan (TRP-04)

Share the helper from HAZ-06: when monitoring flips true, scan overlapping areas once.

### Honest ids (TRP-05)

Until frost/shadow traps are authored: remove those keys from `procgen_loot_tables` biome maps; emit `spike_trap` / `poison_pool` / `falling_trap` only. When content ships, add scenes and map entries in the same commit.

### Falling re-arm (TRP-06)

RESET → brief TELEGRAPH (0.5× first telegraph) → IDLE, or go IDLE only after block returns to ceiling so the next proximity trigger always shows a full telegraph. Chosen: return to IDLE only after ceiling restore so the existing TELEGRAPH state always runs.

### Scene cleanup (TRP-07)

Remove legacy `SpikesMesh` from `spike_trap.tscn` once diorama path is mandatory (it already is in `_ready`).

## Work plan

1. **Forward damage exports in spike + falling `_ready`** — trap scripts. Closes TRP-01.
2. **Derive or document trigger radius vs damage shape; adjust defaults** — trap scripts + scenes. Closes TRP-02.
3. **Honor `entry` position in `room_trap_content`** — `room_trap_content.gd`. Closes TRP-03.
4. **ACTIVE overlap scan** — with HAZ-06 on `trap_damage_area`. Closes TRP-04.
5. **Remove fake frost/shadow ids from loot tables** (or add scenes). Closes TRP-05.
6. **Falling trap ceiling restore before IDLE** — `falling_trap.gd`. Closes TRP-06.
7. **Delete legacy SpikesMesh from tscn** — `spike_trap.tscn`. Closes TRP-07.

## Data and schema changes

Optional future `content/traps/*.json` with `damage`, `poise`, telegraph/active/cooldown, `scene` — schema under `content/schemas/` when introduced. Not required for steps 1–7. No save migrator.

## Acceptance criteria

- [ ] Changing `spike_trap.damage` in the inspector changes dealt HP (child area matches). (TRP-01)
- [ ] Telegraph radius fully covers the DamageArea horizontal footprint for default scenes. (TRP-02)
- [ ] Room content entry `{ "x": 3 }` places the spike at local x=3. (TRP-03)
- [ ] Player standing in spikes when ACTIVE begins takes damage without leaving and re-entering. (TRP-04)
- [ ] Generated swamp/frost/shadow corridor traps resolve to an existing `.tscn` whose id matches the table name, or the table no longer emits alias ids. (TRP-05)
- [ ] Second proximity trigger on a falling trap shows a telegraph before the block falls. (TRP-06)

## Validation

| Assertion id | Checks |
|--------------|--------|
| `trp.damage.export_forward` | Set script damage 30, assert child area damage 30 after `_ready` |
| `trp.room_content.offset` | Spawn with entry z=5, assert local origin z≈5 |
| `trp.active.scan_hit` | Overlap before enable, enable+scan, assert HP drop |
| `trp.builder.ids_resolve` | For every id in loot tables, `_trap_scene_for_id` returns non-null and path exists |

## Related

- Existing state: [`../existing_codebase/dungeon-traps.md`](../existing_codebase/dungeon-traps.md)
- [`combat-hazards.md`](combat-hazards.md), [`dungeon-builder.md`](dungeon-builder.md), [`procgen-placements.md`](procgen-placements.md)
