# Enemy health bar

A world-space billboard health bar built from two `Sprite3D` quads whose textures are regenerated pixel-by-pixel on every health change, plus a second pair of quads used as an attack-telegraph bar. It is on the live play path: every castle enemy and every training grunt attaches one.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/ui/enemy_health_bar.gd` | `class_name EnemyHealthBar extends Node3D` — 156 lines |
| `apps/game/client/scripts/ui/training_dummy_health_bar.gd` | `extends EnemyHealthBar`; the entire body is `func _on_died() -> void: pass` so respawning dummies keep their bar visible |
| `apps/game/client/scripts/enemies/castle_enemy_base.gd:175-180` | attaches it as a child named `HealthBar`, sized by `get_hp_bar_height()` |
| `apps/game/client/scripts/enemies/training_grunt.gd:59` | attaches the training-dummy subclass instead |

## How it works

### Geometry constants
`enemy_health_bar.gd:6-13`: texture `BAR_TEX_W = 32` × `BAR_TEX_H = 4` px for health, `ATTACK_BAR_TEX_H = 3` px for the telegraph; world size `BAR_WORLD_W = 1.1` × `BAR_WORLD_H = 0.12` m; telegraph `ATTACK_BAR_WORLD_H = 0.08` m at `ATTACK_BAR_OFFSET_Y = -0.16` m; `DEFAULT_HEIGHT = 2.2` m above the enemy origin.

`BAR_WORLD_H` and `ATTACK_BAR_WORLD_H` are declared but never read — every sprite's scale comes from `pixel_size = BAR_WORLD_W / BAR_TEX_W` (`= 0.034375`), so the on-screen height is `BAR_TEX_H * pixel_size = 0.1375` m rather than the declared `0.12`.

### Setup
`setup(health, height_offset = 2.2)` (`:26`) stores the `Health` reference, sets `position.y`, builds the sprites, connects `health_changed` and `died`, and seeds the fill from `health.current` / `health.max_health`.

`_build_sprites()` (`:35`) creates `Background` and `Fill` `Sprite3D`s. Both use `BILLBOARD_ENABLED`, `TEXTURE_FILTER_NEAREST`, `pixel_size = 0.034375`, and `SHADOW_CASTING_SETTING_OFF`. `Fill` is offset `z = -0.02` to sit in front. `_build_attack_sprites()` (`:60`) adds `AttackBackground` and `AttackFill` with the same settings at `y = -0.16`, both `visible = false`.

### Texture generation
`_make_bar_texture(color, fill_ratio, bar_height = 4)` (`:115`) allocates a `32 × bar_height` `Image` per call, fills it transparent, computes `fill_w = round((32 - 2) * clamp(fill_ratio, 0, 1))`, and writes every pixel: a 1 px `Color(0.02, 0.02, 0.02)` border on all four sides, `color` for `x` in `[1, 1 + fill_w)`, transparent elsewhere. It then wraps the image with `ImageTexture.create_from_image`.

`_on_health_changed(current, max_value)` (`:141`) calls `_make_bar_texture` again on **every** health change — so each hit allocates a fresh `Image` and a fresh `ImageTexture`. It then also scales the sprite: `_fill_sprite.scale.x = max(ratio, 0.001)` and `position.x = inner_w * 0.5 - fill_w * 0.5` where `inner_w = 1.1 - 0.03`. The bar is therefore shrunk twice — once by regenerating the texture with fewer filled pixels, once by scaling the quad — so the visible fill is proportional to `ratio²`. Finally `visible = ratio > 0.0`.

`_on_died()` (`:154`) sets `visible = false`. `training_dummy_health_bar.gd:6-7` overrides it with `pass`.

### Attack telegraph
- `begin_attack_telegraph(_duration)` (`:88`) shows both telegraph sprites and calls `set_attack_telegraph_progress(0.0)`. The `_duration` parameter is unused (leading underscore).
- `set_attack_telegraph_progress(ratio)` (`:96`) regenerates `AttackFill`'s texture in `Color(0.95, 0.55, 0.15)` and applies the same double-shrink as the health bar.
- `hide_attack_telegraph()` (`:108`) hides both.

Callers: `castle_enemy_base.gd:193,199,433` and `training_grunt.gd:105,111,149`, where `:433` / `:149` drive progress from `elapsed / _windup_duration` every physics frame — one `Image` allocation and one `ImageTexture` creation per enemy per frame while any windup is active.

### Facing
`_process(_delta)` (`:130`) fetches `PixelDioramaViewport.get_gameplay_camera()` every frame and calls `look_at(global_position + to_camera_flattened, Vector3.UP)`, where `to_camera.y` is zeroed. This runs in addition to `BILLBOARD_ENABLED` on all four sprites, so the bar is oriented twice by two independent mechanisms.

## Contracts
- Public API: `setup(Health, float)`, `begin_attack_telegraph(float)`, `set_attack_telegraph_progress(float)`, `hide_attack_telegraph()`.
- Consumes `Health.health_changed(current, max)` and `Health.died`.
- Depends on the `PixelDioramaViewport` autoload exposing `get_gameplay_camera() -> Camera3D`.
- Enemies must supply `get_hp_bar_height()`; `castle_enemy_base.gd:179` passes its result as `height_offset`.
- Child node names created: `Background`, `Fill`, `AttackBackground`, `AttackFill`. The parent names the bar node itself `HealthBar` (`castle_enemy_base.gd:177`).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Billboard HP bar per enemy | IMPLEMENTED | `enemy_health_bar.gd:26-57` |
| Attack telegraph bar | IMPLEMENTED | `enemy_health_bar.gd:60-113`; driven from `castle_enemy_base.gd:433` |
| Fill proportionality | BROKEN — the texture fill and the quad scale are both reduced by `ratio`, so the drawn fill is `ratio²`; at 50 % HP the bar reads 25 % | `enemy_health_bar.gd:145-150` (texture) and `:150` (`scale.x = ratio`) |
| Per-change texture allocation | PARTIAL — a new `Image` plus `ImageTexture` on every `health_changed` and every telegraph frame | `enemy_health_bar.gd:100-101`, `:145-146`; caller `castle_enemy_base.gd:433` |
| Authored bar art | ABSENT — bars are generated per pixel; `apps/game/client/**/*.png` returns 0 files | `enemy_health_bar.gd:115-127` |
| Double billboarding | PARTIAL — `BILLBOARD_ENABLED` on all four sprites plus a per-frame `look_at` | `enemy_health_bar.gd:42,51,67,78` and `:130-138` |
| `BAR_WORLD_H` / `ATTACK_BAR_WORLD_H` | STUB — declared, never read; actual height derives from `pixel_size` | `enemy_health_bar.gd:10-11` |
| `begin_attack_telegraph` duration | STUB — parameter is `_duration`, unused | `enemy_health_bar.gd:88` |
| Enemy name label | ABSENT — no `Label3D`, no text of any kind | `enemy_health_bar.gd:35-85` creates only `Sprite3D`s |
| Chip / delayed damage feedback | ABSENT — the fill snaps to the new value with no tween or trailing bar | `enemy_health_bar.gd:141-151` |
| Poise or stagger bar | ABSENT — only health and attack-windup bars exist | `enemy_health_bar.gd:15-23` declares four sprites total |
| Status-effect indicators above enemies | ABSENT — statuses are shown only on the player HUD | `combat_hud.gd:183-203` is the only status-row builder |
| Elite / boss bar differentiation | ABSENT — every enemy gets the same 32×4 red bar; bosses use the separate HUD bar at `combat_hud.gd:329-351` | `enemy_health_bar.gd:37` hardcodes `Color(0.9, 0.15, 0.1)` |
| Distance-based fade or hiding | ABSENT — `visible` depends only on `ratio > 0.0` | `enemy_health_bar.gd:151` |
| Damage-number integration | ABSENT from this file | no reference to damage numbers in `enemy_health_bar.gd` |

## Related
- Improvement plan: [`../actual_improvements/ui/enemy_health_bar.md`](../actual_improvements/ui/enemy_health_bar.md)
- [`combat_hud.md`](combat_hud.md) · [`status_icon_atlas.md`](status_icon_atlas.md)
- [`../enemies.md`](../enemies.md) · [`../combat-core.md`](../combat-core.md) · [`../hit-feedback.md`](../hit-feedback.md) · [`../debug-arenas.md`](../debug-arenas.md)
