# Diorama anim controller — improvement plan

## Status: FINISHED

## Current state

`DioramaAnimController` builds an `AnimationPlayer` per rig, arbitrates clips through a six-level priority stack, stretches attack clips onto weapon phase timings, and mirrors every call to the first-person viewmodel controller through `mirror_apply`. Events resolve via `visual.get_path_to(self)`, method tracks fire `footstep_frame` / `swing_frame` / hitbox signals, hosts wire `hitbox_open_frame` / `hitbox_close_frame`, and `diorama_anim_suite.gd` covers all gaps below. See [`../existing_codebase/diorama-anim-controller.md`](../existing_codebase/diorama-anim-controller.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| ANC-01 | P0 | ~~`_resolve_events_path` required `visual.is_ancestor_of(self)`, leaving `_events_path` always `""`.~~ **Closed.** Uses `get_path_to` plus resolve check. | `diorama_anim_controller.gd:_resolve_events_path` |
| ANC-02 | P0 | ~~`anim_footstep` never fired; locomotion fallback suppressed.~~ **Closed.** Method tracks compile with resolved path; `has_footstep_markers()` gates fallback. | `anim_footstep`, `locomotion.gd:403-406` |
| ANC-03 | P0 | ~~`anim_swing_vfx` never fired.~~ **Closed.** Swing markers emit `swing_frame`. | `anim_swing_vfx`, `player_anim_director.gd`, `castle_enemy_base.gd` |
| ANC-04 | P1 | ~~Enemy hitboxes could not be animation-driven.~~ **Closed.** `hitbox_open_frame` / `hitbox_close_frame` signals; hosts connect. | `weapon_controller.gd:333-336`, `castle_enemy_base.gd:182-193` |
| ANC-05 | P1 | ~~Missing clips returned silently.~~ **Closed.** `_report_missing` deduplicates per bind. | `diorama_anim_controller.gd:_report_missing` |
| ANC-06 | P1 | ~~Second flinch during stagger window produced no reaction.~~ **Closed.** `play_flinch` re-enters; `_play_local` seeks to 0 on same non-looping clip. | `play_flinch`, `_play_local` |
| ANC-07 | P1 | ~~Mirror state via private field writes; stagger `speed_scale` not propagated.~~ **Closed.** `mirror_apply` fans out priority, locomotion, clip, blend, and scale. | `mirror_apply`, `_begin_action` |
| ANC-08 | P1 | ~~Locomotion rate used fixed reference speeds.~~ **Closed.** Stride-driven scaling via `AnimLibrary.clip_meta`. | `_locomotion_speed_scale`, `clip_meta` |
| ANC-09 | P1 | ~~Empty rest pose left `is_bound()` false forever.~~ **Closed.** Warning plus deferred `tree_entered` retry. | `_finish_bind:103-110` |
| ANC-10 | P1 | ~~Freed mirrors stayed in `_mirrors`.~~ **Closed.** `_live_mirrors` prunes; `remove_mirror` on viewmodel rebuild. | `_live_mirrors`, `player_anim_director.gd:155` |
| ANC-11 | P2 | ~~`_compiled_attacks` grew unbounded.~~ **Closed.** LRU cap of 24 entries. | `ATTACK_CACHE_LIMIT`, `_attack_cache_order` |
| ANC-12 | P2 | ~~`revive()` did not reset combo.~~ **Closed.** `revive()` calls `reset_combo()`. | `revive:426` |
| ANC-13 | P2 | ~~Compiled attacks shared default library namespace.~~ **Closed.** `RUNTIME_LIBRARY_NAME = &"runtime"`. | `_runtime_library`, `_ensure_attack_clip` |
| ANC-14 | P2 | ~~`_on_animation_finished` used `block_hold` prefix workaround.~~ **Closed.** Runtime attacks namespaced; block clips still ignored by `block_` prefix. | `_on_animation_finished:596-606` |

## Target design

Implemented as specified: `get_path_to` events path, hitbox signals on hosts, `_report_missing` diagnostics, `mirror_apply` / `_live_mirrors` / `remove_mirror`, directional flinch with re-entry, stride-driven locomotion via `clip_meta`, `runtime` library with LRU attack cache, and `revive()` combo reset.

## Work plan

1. **Fix `_resolve_events_path`** — done.
2. **Add hitbox signals and rewire hosts** — done.
3. **Add `_report_missing` and empty-rest-pose retry** — done.
4. **Mirror API (`mirror_apply`, `_live_mirrors`, `remove_mirror`)** — done.
5. **Directional flinch and re-entry** — done.
6. **Stride-driven locomotion and `select_locomotion_clip`** — done.
7. **Runtime library, LRU cache, `revive()` combo reset** — done.

## Data and schema changes

No JSON content, schema, or save changes. `stride_m` and `contacts` live in `DioramaAnimLibrary.CLIPS` and are exposed through `clip_meta()`.

## Acceptance criteria

- [x] `_events_path` is non-empty for player, viewmodel, enemy, boss, and training dummy layouts. (ANC-01)
- [x] Walking the player emits `footstep_frame` at clip contact times; footstep SFX/VFX produced. (ANC-02)
- [x] Every melee swing emits `swing_frame` and weapon trail VFX. (ANC-03)
- [x] Enemy hitbox opens/closes on animation frames via signals. (ANC-04)
- [x] Missing clips log exactly one warning per bind. (ANC-05)
- [x] Empty rest pose warns and does not permanently block bind. (ANC-09)
- [x] Freed mirror pruned; fan-out calls do not error. (ANC-10)
- [x] Staggered viewmodel `speed_scale` matches body. (ANC-07)
- [x] Two hits 0.1 s apart produce two flinch reactions. (ANC-06)
- [x] Locomotion `speed_scale` stays inside `[0.5, 2.2]`. (ANC-08)
- [x] Attack cache never exceeds 24 entries. (ANC-11)
- [x] Compiled attacks live under `runtime/` library. (ANC-13)
- [x] `revive()` resets combo index. (ANC-12)

## Validation

Suite `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd`, category `diorama_anim`:

| Test id | Assertion |
|---------|-----------|
| `diorama_anim.events_path_resolves` | Player and enemy layouts: `_events_path != ""` and path resolves |
| `diorama_anim.method_signals_fire` | `anim_*` handlers emit footstep, swing, and hitbox signals |
| `diorama_anim.missing_clip_warns` | `_report_missing` deduplicates per bind |
| `diorama_anim.empty_rest_pose_warns` | Bare visual leaves controller unbound |
| `diorama_anim.mirror_survives_free` | Freed mirror pruned from `_mirrors` |
| `diorama_anim.mirror_speed_scale_matches` | Mirror `speed_scale` matches body on stagger |
| `diorama_anim.flinch_retriggers` | Second `play_flinch()` restarts from time 0 |
| `diorama_anim.locomotion_scale_in_range` | `speed_scale` inside clamp band for walk/run speeds |
| `diorama_anim.attack_cache_bounded` | Cache and library capped at 24 |
| `diorama_anim.revive_resets_combo` | Combo index 0 after revive |
| `diorama_anim.hitbox_signal_wired` | Weapon and enemy hosts connect hitbox signals |

Manual checklist:

- Footstep timing lands on visual foot contact at walk, jog, and run speeds.

## Related
- Current behavior: [`../existing_codebase/diorama-anim-controller.md`](../existing_codebase/diorama-anim-controller.md)
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
- [`player-anim-director.md`](player-anim-director.md), [`combat-core.md`](combat-core.md), [`vfx-service.md`](vfx-service.md), [`validation-suites.md`](validation-suites.md)
