# Quality bar — replacing placeholders

Acceptance checks when replacing PLACEHOLDER / STUB / FAKE / BROKEN / ABSENT surfaces listed in [`../existing_codebase/00-PLACEHOLDER-INVENTORY.md`](../existing_codebase/00-PLACEHOLDER-INVENTORY.md). Grounded in systems that already exist under `apps/game/client/`, `content/`, `services/backend/`, and `apps/web/`. Doc conventions: [`../DOC-CONVENTIONS.md`](../DOC-CONVENTIONS.md).

## Done criteria (per surface)

A replacement is done only if all apply:

1. **Player-facing** — no generator/sine/ColorRect/emoji/Unicode stand-in remains for that surface.
2. **Wired** — loaded through the real catalog/scene/profile path; fallbacks are error-only.
3. **Honest** — rewards, quests, and results match the event that occurred.
4. **Readable at play speed** — telegraphs, recovery, and hit confirmation are clear.
5. **Tested** — suite under `scripts/validation/suites/` updated when automatable; otherwise a short manual checklist.
6. **Authored when the surface is art** — characters, weapons, and props that claim to be pixel/voxel are authored from discrete cells, not procedural boxes with a pixel filter. See [`character-authoring.md`](character-authoring.md).

## Domain checks

### Character authoring (P0 art direction)

| Criterion | Done | Fail |
|-----------|------|------|
| Source of geometry | Committed voxel-authored `ArrayMesh` parts from `tools/voxel-import/` | Runtime `BoxMesh` from `DioramaCharacterSkin._build_humanoid` |
| Grid | Every vertex on a `VoxelGrid.EDGE` (0.04 m) boundary | Arbitrary float sizes in `PROFILES` |
| Palette | Vertex colours snap to `PixelDioramaStyle.PALETTES` | Free RGB / procedural `cell_hash` tint as the silhouette |
| Rig contract | Manifest pivots match existing animation track names | Renamed pivots that break clips |
| Equipment visuals | Items with `"visual"` change the body in one frame | Stats change, silhouette does not |
| Scale | No non-uniform `Root.scale` on any character | `height`/`bulk` via `root.scale` |

### Combat

| Criterion | Done | Fail |
|-----------|------|------|
| Hit confirmation | Authored SFX + feedback on diorama body | Generator beep; pulse on unused mesh |
| Swing phases | Windup/active/recovery match hitbox | Timer/anim disagree |
| Guard | Distinct block/parry feedback + stamina cost | Same cue for all |
| Heal | Dedicated heal anim/SFX | Heal reuses stagger |
| Lunge | Non-zero, collision-safe motion from `get_attack_lunge_velocity()` | Still `Vector3.ZERO` |

### Audio

| Criterion | Done | Fail |
|-----------|------|------|
| Combat SFX | Streams from `assets/audio/` via `AudioDirector` | Sine/`AudioStreamGenerator` only |
| Biome ambience | Profile OGG plays and stays | `_restore_generator_streams()` clobbers load |

### Loot / UI / meta honesty

| Criterion | Done | Fail |
|-----------|------|------|
| Icons | Item `iconPath` / atlas cells | Unicode-only cells |
| Affix tiers | `affix_roller.gd` respects rarity tables | Flat 1–3 rolls |
| Results | Outcome keys match run mode (castle/waves) | Waves win/fail ignored |
| Escape quests | Complete only on real escape | Complete on any `run_ended` / death |
| Fetch quests | `register_fetch` wired from inventory pickup | Quest impossible to progress |

### Dungeon builder

| Criterion | Done | Fail |
|-----------|------|------|
| Height transitions | Real implementation replacing `pass` | Still no-op |
| Shortcuts | Called from build path with tests | Function exists uncalled |
| Floor 10 | Uses selected biome fantasy | Always Forgotten Sovereign layout |

### Platform

| Criterion | Done | Fail |
|-----------|------|------|
| Online runs | `USE_ONLINE_PROCgen` enabled only with API + parity suites green | Flag flipped without parity |
| CI Godot | Workflow version matches `project.godot` features | 4.4 CI vs 4.7 project |

## Related

- Placeholder inventory: [`../existing_codebase/00-PLACEHOLDER-INVENTORY.md`](../existing_codebase/00-PLACEHOLDER-INVENTORY.md)
- Character authoring plan: [`character-authoring.md`](character-authoring.md)
- Loop integrity: [`00-ADDICTION-AND-FUN.md`](00-ADDICTION-AND-FUN.md)
- Architecture: [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
