# Enemy health bar — improvement plan

## Current state
`enemy_health_bar.gd` draws a 32×4 px health bar and a 32×3 px attack-telegraph bar as billboarded `Sprite3D` quads, regenerating each texture pixel-by-pixel on every update (`enemy_health_bar.gd:115-127`). The fill is reduced twice — once inside the generated texture and once via `scale.x` — so the visible fill is `ratio²` rather than `ratio` (`:145-150`). Telegraph progress is driven every physics frame from `castle_enemy_base.gd:433`, so each winding-up enemy allocates one `Image` and one `ImageTexture` per frame. There is no enemy name, no poise bar, no status indicator, and no elite differentiation. See [`../existing_codebase/ui/enemy_health_bar.md`](../existing_codebase/ui/enemy_health_bar.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| EHB-01 | P0 | The bar lies about remaining health: `_make_bar_texture` already scales the filled pixel count by `ratio`, and then `_fill_sprite.scale.x = maxf(ratio, 0.001)` scales the same quad again, so an enemy at 50 % HP shows a 25 % bar and one at 20 % shows 4 %. | `enemy_health_bar.gd:118` computes `fill_w` from `fill_ratio`; `:145-150` regenerates that texture *and* sets `scale.x = ratio` |
| EHB-02 | P0 | Per-frame texture allocation during every enemy windup: `set_attack_telegraph_progress` creates an `Image` and an `ImageTexture` on each call, and `castle_enemy_base.gd:433` calls it every physics frame per attacking enemy. | `enemy_health_bar.gd:100-101`; caller `castle_enemy_base.gd:433`, `training_grunt.gd:149` |
| EHB-03 | P1 | Bars are procedurally plotted rather than authored art, and the client contains no `.png` at all. | `enemy_health_bar.gd:115-127`; `apps/game/client/**/*.png` returns 0 files |
| EHB-04 | P1 | Enemies are anonymous: no `Label3D`, so the player cannot tell a `castle_guard` from a `castle_archer` without reading the model, and elite variants are indistinguishable. | `enemy_health_bar.gd:35-85` creates only `Sprite3D`s; fill color is the hardcoded `Color(0.9, 0.15, 0.1)` at `:37` |
| EHB-05 | P1 | No poise or stagger bar, despite poise being a combat system with `poiseDamage` in the talent effect list. | `enemy_health_bar.gd:15-23` declares four sprites; `talents_ui.gd:130` lists `poiseDamage` as a real stat |
| EHB-06 | P1 | No chip or delayed-damage presentation: the fill snaps, so a large hit and a small hit read the same. | `enemy_health_bar.gd:141-151` has no tween |
| EHB-07 | P1 | Double orientation: all four sprites set `BILLBOARD_ENABLED` and `_process` additionally calls `look_at` every frame on every enemy bar. One of the two is redundant work scaling with enemy count. | `enemy_health_bar.gd:42,51,67,78` vs `:130-138` |
| EHB-08 | P2 | `BAR_WORLD_H` and `ATTACK_BAR_WORLD_H` are dead constants; the real drawn height is `BAR_TEX_H * pixel_size = 0.1375` m, not the declared `0.12`. | `enemy_health_bar.gd:10-11`, `:44` |
| EHB-09 | P2 | `begin_attack_telegraph(_duration)` ignores its duration argument, so the bar cannot pace itself or distinguish a fast jab from a slow overhead. | `enemy_health_bar.gd:88` |
| EHB-10 | P2 | Bars never fade with distance or occlusion, so a crowded room becomes a wall of red rectangles. | `enemy_health_bar.gd:151` sets `visible` from `ratio > 0.0` only |
| EHB-11 | P2 | No status indicators above enemies: a burning or frozen enemy shows nothing, while the player's own statuses are on the HUD. | `combat_hud.gd:183-203` is the only status-row builder in the repo |

## Target design

### Authored 9-slice bar art with shader-driven fill
Replace the four generated textures with two authored sprites and a fill shader, so nothing is regenerated at runtime.

Assets (all `filter=false`, `mipmaps=false`, lossless):
- `assets/ui/enemy_bar_frame.png` — 34×6 px, 1 px dark border plus a 1 px inner bevel, transparent interior.
- `assets/ui/enemy_bar_fill.png` — 32×4 px, a vertical 3-value gradient in the `PaletteTheme.CASTLE` accent ramp, tinted per bar kind via `modulate`.
- `assets/ui/enemy_bar_poise.png` — 32×2 px.

New shader `assets/shaders/bar_fill_3d.gdshader` with uniforms `fill: float` (0-1), `chip: float` (0-1), `fill_color: vec4`, `chip_color: vec4`. It discards fragments where `UV.x > chip`, draws `chip_color` where `fill < UV.x <= chip`, and `fill_color` where `UV.x <= fill`. Updating a bar becomes two `set_shader_parameter` calls with zero allocation, which resolves EHB-01 and EHB-02 together: the quad is never scaled and no texture is rebuilt.

Rejected alternative: keeping `_make_bar_texture` and simply deleting the `scale.x` line. It fixes the lie but leaves per-frame allocation during every windup, which is the more expensive of the two bugs at scale.

### Node structure
```
HealthBar (Node3D, position.y = get_hp_bar_height())
├── Nameplate (Label3D, billboard = BILLBOARD_ENABLED, font_size 12, outline 2, y = 0.20)
├── HealthFrame (Sprite3D, enemy_bar_frame.png)
├── HealthFill  (Sprite3D, enemy_bar_fill.png, material = bar_fill_3d, z = -0.02)
├── PoiseFrame  (Sprite3D, enemy_bar_frame.png, y = -0.10, visible = false)
├── PoiseFill   (Sprite3D, enemy_bar_poise.png, material = bar_fill_3d, y = -0.10, z = -0.02)
├── TelegraphFrame (Sprite3D, y = -0.20, visible = false)
├── TelegraphFill  (Sprite3D, material = bar_fill_3d, y = -0.20, z = -0.02, visible = false)
└── StatusStrip (Node3D, y = 0.34)      # up to 4 Sprite3D cells, 16px atlas cells
```

Every sprite keeps `BILLBOARD_ENABLED` and the per-frame `look_at` in `_process` is deleted (EHB-07). `pixel_size` stays `BAR_WORLD_W / BAR_TEX_W`; `BAR_WORLD_H` and `ATTACK_BAR_WORLD_H` are removed (EHB-08).

### Bar kinds and elite differentiation
```gdscript
enum BarKind { NORMAL, ELITE, BOSS }
func setup(health: Health, height_offset: float, kind: BarKind = BarKind.NORMAL, display_name: String = "") -> void
```

| Kind | Frame `modulate` | Fill color | World width | Nameplate |
|---|---|---|---|---|
| `NORMAL` | `Color(1, 1, 1)` | `Color(0.86, 0.16, 0.12)` | `1.10` m | shown within 12 m |
| `ELITE` | `Color(1.0, 0.84, 0.42)` | `Color(0.92, 0.30, 0.14)` | `1.45` m | always shown |
| `BOSS` | — | — | — | suppressed; the HUD bar at `combat_hud.gd:329-351` owns boss presentation |

`castle_enemy_base.gd:175-180` passes `kind` from a new `"tier"` key on the enemy definition and `display_name` from `EnemyCatalog.get_definition(id).name`, routed through `tr()` (EHB-04).

### Poise bar
Shown only while `poise_current < poise_max`; hidden again `1.2` s after poise refills. Driven by a new `poise_changed(current, max)` signal on the enemy's poise component (see [`../combat-core.md`](../combat-core.md)) rather than polled (EHB-05).

### Chip damage
On `health_changed`, set `fill` immediately and tween `chip` from its old value to the new `fill` over `0.35` s with `Tween.EASE_OUT`, `TRANS_CUBIC`, after a `0.15` s hold. `chip_color` is `Color(1.0, 0.92, 0.86, 0.85)`. Store the active `Tween` and `kill()` it before starting a new one so rapid hits do not stack tweens (EHB-06).

### Telegraph pacing
`begin_attack_telegraph(duration)` stores the duration and drives its own progress from `_process`, so callers stop pushing per-frame ratios:

```gdscript
func begin_attack_telegraph(duration: float) -> void   # stores duration, resets elapsed, shows frames
func cancel_attack_telegraph() -> void                 # replaces hide_attack_telegraph
```

`set_attack_telegraph_progress` is kept as a deprecated shim for one release. `castle_enemy_base.gd:433` and `training_grunt.gd:149` drop their per-frame calls. The frame `modulate` reddens as `elapsed / duration` crosses `0.75`, giving the player a parry cue that scales with attack speed (EHB-09).

### Distance fade and crowd control
In `_process` at 10 Hz, compute the camera distance once per bar:

| Distance | Behavior |
|---|---|
| `< 12 m` | full alpha, nameplate visible |
| `12`-`22 m` | alpha lerped `1.0` → `0.35`, nameplate hidden |
| `> 22 m` | `visible = false` |

Bars at full health and not recently damaged fade to alpha `0.0` after `3.0` s unless the enemy is the lock-on target (`LockOn.current_target`), which removes the wall of red rectangles in a crowded room (EHB-10).

### Status strip
Up to four `Sprite3D` cells fed by `UISymbolAtlas` status cells (see [`status_icons_glyphs.md`](status_icons_glyphs.md)), 16 px cells at `pixel_size` matching the bar. Driven by the enemy's `StatusController.statuses_changed` signal, same as the player HUD (EHB-11).

## Work plan
1. **Fill correctness** — delete the `scale.x` / `position.x` manipulation and keep only the texture fill, restoring linear proportionality immediately (EHB-01).
2. **Shader fill** — add `bar_fill_3d.gdshader` and the two authored frame/fill PNGs; replace `_make_bar_texture` with `set_shader_parameter`; delete `_make_bar_texture` and the dead world-height constants (EHB-02, EHB-03, EHB-08).
3. **Billboard cleanup** — delete `_process`'s `look_at` block (EHB-07).
4. **Node restructure** — add `Nameplate`, `PoiseFrame`/`PoiseFill`, rename telegraph nodes, add `StatusStrip`; extend `setup()` with `kind` and `display_name`; add `"tier"` to the enemy schema and pass it from `castle_enemy_base.gd:175-180` (EHB-04).
5. **Chip damage** — add the `chip` tween with kill-on-restart (EHB-06).
6. **Poise** — add `poise_changed` to the poise component and the poise bar wiring (EHB-05).
7. **Telegraph self-pacing** — `begin_attack_telegraph(duration)` drives itself; add `cancel_attack_telegraph`; remove per-frame calls from `castle_enemy_base.gd:433` and `training_grunt.gd:149` (EHB-09).
8. **Distance fade** — 10 Hz distance check, alpha ramp, idle fade with lock-on exemption (EHB-10).
9. **Status strip** — bind `StatusController.statuses_changed` and draw up to four atlas cells (EHB-11).

Step 1 is a two-line change that fixes the honesty bug on its own; every later step is additive.

## Data and schema changes
- `content/schemas/enemy-definition.v1.json`: add `"tier": {"type": "string", "enum": ["normal", "elite", "boss"], "default": "normal"}`.
- Enemy definitions under `content/enemies/` gain `tier`; existing files default to `normal`, so behavior is unchanged on landing.
- `apps/game/client/translations/strings.csv`: add `ENEMY_NAME_*` keys for each enemy id used by the nameplate.
- New assets: `assets/ui/enemy_bar_frame.png` (34×6), `assets/ui/enemy_bar_fill.png` (32×4), `assets/ui/enemy_bar_poise.png` (32×2), `assets/shaders/bar_fill_3d.gdshader`.
- No save-format change; no `save_migrator.gd` bump.

## Acceptance criteria
- [ ] An enemy at exactly 50 % health draws a fill occupying 50 % ± 1 px of the bar's inner width.
- [ ] `_fill_sprite.scale` is `Vector3.ONE` at every health value.
- [ ] `enemy_health_bar.gd` contains no `Image.create` and no `ImageTexture.create_from_image`.
- [ ] Ten enemies winding up simultaneously allocate zero `Image` objects per frame.
- [ ] `enemy_health_bar.gd` declares no constant with zero readers.
- [ ] `_process` contains no `look_at` call.
- [ ] An enemy whose definition sets `tier: "elite"` draws a gold-tinted frame at `1.45` m width with a persistent nameplate.
- [ ] A `boss`-tier enemy draws no nameplate and no world bar.
- [ ] Taking a 30 % hit leaves a lighter chip segment that drains over `0.35` s after a `0.15` s hold; two hits in `0.1` s produce one tween, not two.
- [ ] A staggered enemy shows a poise bar that hides `1.2` s after poise refills.
- [ ] `begin_attack_telegraph(1.2)` fills the telegraph bar over `1.2` s with no caller-side progress updates, and the frame reddens past 75 %.
- [ ] `castle_enemy_base.gd` and `training_grunt.gd` contain no `set_attack_telegraph_progress` call.
- [ ] A bar 25 m from the camera is not visible; at 17 m its alpha is between `0.35` and `1.0`.
- [ ] An undamaged, unlocked enemy's bar reaches alpha `0.0` after `3.0` s; locking on restores it.
- [ ] A burning enemy shows the `burn` atlas cell above its bar.

## Validation
Extend `apps/game/client/scripts/validation/suites/combat_suite.gd`:

| Test id | Assertion |
|---|---|
| `ehb.fill_linear` | for `ratio` in `[0.25, 0.5, 0.75]`, the shader `fill` parameter equals `ratio` within `0.01` and `scale == Vector3.ONE` |
| `ehb.no_runtime_image` | `enemy_health_bar.gd` contains neither `Image.create` nor `create_from_image` |
| `ehb.telegraph_no_alloc` | drive 60 frames of telegraph on 10 bars and assert `Performance.get_monitor(OBJECT_COUNT)` is unchanged within a tolerance of 4 |
| `ehb.no_dead_constants` | `enemy_health_bar.gd` contains neither `BAR_WORLD_H` nor `ATTACK_BAR_WORLD_H` |
| `ehb.single_billboard` | `enemy_health_bar.gd` contains no `look_at` |
| `ehb.tier_elite_style` | `setup(..., BarKind.ELITE)` yields frame `modulate` `Color(1.0, 0.84, 0.42)` and a visible `Nameplate` |
| `ehb.tier_boss_suppressed` | `setup(..., BarKind.BOSS)` leaves `Nameplate.visible == false` and the frame hidden |
| `ehb.chip_tween_single` | two `health_changed` events `0.1` s apart leave exactly one active `Tween` |
| `ehb.poise_bar_visibility` | emitting `poise_changed(3, 10)` shows `PoiseFrame`; `poise_changed(10, 10)` hides it after `1.2` s |
| `ehb.telegraph_self_paced` | `begin_attack_telegraph(1.0)` then advancing `0.5` s yields shader `fill` near `0.5` with no caller updates |
| `ehb.callers_no_progress_push` | `castle_enemy_base.gd` and `training_grunt.gd` contain no `set_attack_telegraph_progress` |
| `ehb.distance_cull` | a bar at 25 m reports `visible == false`; at 17 m its alpha is in `(0.35, 1.0)` |
| `ehb.idle_fade_lockon_exempt` | after 4 s idle, alpha is `0.0`; setting the bar's enemy as `LockOn.current_target` restores alpha to `1.0` |
| `ehb.status_strip` | applying `burn` to the enemy adds one `Sprite3D` to `StatusStrip` whose texture region is the `burn` cell |
| `ehb.training_dummy_persists` | `training_dummy_health_bar.gd` still overrides `_on_died` and the bar stays visible after `died` |

## Related
- Existing behavior: [`../existing_codebase/ui/enemy_health_bar.md`](../existing_codebase/ui/enemy_health_bar.md)
- [`combat_hud.md`](combat_hud.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md)
- [`../enemies.md`](../enemies.md) · [`../combat-core.md`](../combat-core.md) · [`../hit-feedback.md`](../hit-feedback.md) · [`../bosses.md`](../bosses.md)
