# Title screen — improvement plan

## Current state
`title_screen.tscn` is 13 lines with no child nodes; the whole screen is built in `title_screen.gd:22-91` out of `ColorRect`s and `Label`s. The game's masthead is the word `AUMBRYE` in the shared menu-title style, the tower is six stacked translucent rectangles (`:102-108`), and the ornament is the Unicode string `"◆ ◆ ◆"` (`:49`). The version is a hardcoded literal (`:88`), nothing is localized, and the hint pulses forever with no reduced-motion gate. See [`../existing_codebase/ui/title_screen.md`](../existing_codebase/ui/title_screen.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| TTL-01 | P0 | The first screen of the game has no art. The title is body text, the tower is six rectangles, and the ornament is a Unicode diamond string — this is the storefront-screenshot surface. | `title_screen.gd:49`, `:54-58`, `:102-108`; `title_screen.tscn:5-13` has no children; `apps/game/client/**/*.png` returns 0 files |
| TTL-02 | P1 | The scene is an empty script host, so the screen cannot be art-directed, previewed, or edited in the Godot editor at all. | `title_screen.tscn` is 13 lines with one node |
| TTL-03 | P1 | The version string is a hardcoded literal that will silently go stale. | `:88` `"Early Access — Pixel Diorama build"` |
| TTL-04 | P1 | Nothing is localized: six English literals including a three-sentence lore paragraph built by string concatenation. | `:49`, `:55`, `:61`, `:73-77`, `:82`, `:88`; 0 `tr(` calls |
| TTL-05 | P1 | The hint pulse runs unconditionally in `_process` with no reduced-motion option. | `:115-119` |
| TTL-06 | P2 | The transition to the main menu is a bare `change_scene_to_file` with no fade, so the screen cuts. | `:122-123` |
| TTL-07 | P2 | The title is save-state blind — a returning player with three wardens sees exactly what a first-time player sees. | `:12-19` reads nothing from `LocalSave` |
| TTL-08 | P2 | The vignette `ColorRect` is added after the tower host, so the decorative tower is dimmed by 35 % black; the layering is accidental. | `:29-34` adds the vignette at `:32` before `_build_tower_silhouette` is called at `:34`, but the tower is parented to `backdrop`, which sits below the vignette |
| TTL-09 | P2 | No title music sting or ambience distinct from the shared menu track. | `:17` calls the same `play_menu_music()` the main menu uses |

## Target design

### Authored scene
`title_screen.tscn` becomes a real scene with authored nodes, and `title_screen.gd` shrinks to boot logic plus the advance handler:

```
TitleScreen (Control, FULL_RECT)
├── TextureRect "Background"      # assets/ui/title_bg.png, 640×360, STRETCH_KEEP_ASPECT_COVERED, NEAREST
├── TextureRect "TowerParallax"   # assets/ui/title_tower.png, 320×360, centered, NEAREST
├── ColorRect   "Vignette"        # shader-based radial vignette, MOUSE_FILTER_IGNORE
├── TextureRect "Logo"            # assets/ui/title_logo.png, 320×96, PRESET_CENTER_TOP, offset_top 48
├── VBoxContainer "TextStack"     # PRESET_CENTER, separation 12
│   ├── Label "Subtitle"          # theme_type_variation = BodyText
│   ├── TextureRect "Rule"        # assets/ui/title_rule.png, 240×3
│   └── Label "Lore"              # BodyText, autowrap, max 420 px wide
├── HBoxContainer "Prompt"        # PRESET_CENTER_BOTTOM, offset_bottom -72
│   ├── TextureRect "PromptGlyph" # UISymbolAtlas cell for ui_accept on the active device
│   └── Label "PromptLabel"       # HintText
└── Label "VersionLabel"          # PRESET_BOTTOM_RIGHT, HintText
```

Assets, all `filter=false`, `mipmaps=false`, lossless:

| Asset | Size | Notes |
|---|---|---|
`assets/ui/title_bg.png` | 640×360 | authored pixel scene of the tower approach, 16-colour `PaletteTheme.UMBRAL` ramp |
`assets/ui/title_tower.png` | 320×360 | foreground tower with alpha, drifts `±6` px on a 14 s sine for parallax |
`assets/ui/title_logo.png` | 320×96 | the wordmark, replacing the `AUMBRYE` text label |
`assets/ui/title_rule.png` | 240×3 | ornamental divider, replacing the `ColorRect` at `:66-69` and the `"◆ ◆ ◆"` label at `:49` |

The vignette moves to a `ShaderMaterial` on a single full-rect `ColorRect` placed above the background and tower but below `Logo`, so the layering is explicit instead of emergent (TTL-01, TTL-02, TTL-08).

Rejected alternative: keeping the procedural tower and only adding a logo PNG. The tower is the visual identity of the screen; six translucent rectangles cannot carry it, and leaving it procedural keeps the screen un-art-directable.

### Device-aware prompt
`PromptGlyph` resolves the `ui_accept` cell from `UISymbolAtlas` (see [`status_icons_glyphs.md`](status_icons_glyphs.md)) and rebuilds on `UISymbolBus.symbols_invalidated`, so plugging in a pad swaps the glyph live. `PromptLabel` uses `TITLE_PROMPT`, phrased so it works with a glyph (`"to enter the tower"`) (TTL-04 support).

### Version from project data
`VersionLabel` reads `ProjectSettings.get_setting("application/config/version")` and appends the short git SHA written into `res://build_stamp.json` by the export step, falling back to `"dev"` when the file is absent (TTL-03).

### Save-aware framing
When `LocalSave.has_playable_character()` is true, the subtitle uses `TITLE_SUBTITLE_RETURNING` and the lore paragraph is replaced by a one-line status: `"{name} — floor {n}"` from the most recent slot in `LocalSave.list_character_slots()`. First-time players keep the full lore paragraph (TTL-07).

### Motion and transition
- The tower parallax and the prompt pulse are both driven by one `Tween` created in `_ready` and skipped entirely when `AccessibilitySettings.reduced_motion` is on; the pulse leaves `modulate.a = 1.0` in that case (TTL-05).
- Advancing plays a `0.25` s fade to black through a new shared `SceneTransition` autoload before `change_scene_to_file`, and the main menu fades in over `0.2` s (TTL-06).

### Localization
Keys added to `apps/game/client/translations/strings.csv`: `TITLE_SUBTITLE`, `TITLE_SUBTITLE_RETURNING`, `TITLE_LORE`, `TITLE_PROMPT`, `TITLE_RETURNING_STATUS`, `TITLE_VERSION_FORMAT`. The lore paragraph becomes one CSV cell rather than three concatenated literals (TTL-04).

### Audio
`AudioDirector` gains `play_title_theme()` with a dedicated cue id and a `0.8` s crossfade into the menu track when advancing, so the title has its own musical identity (TTL-09).

## Work plan
1. **Scene authoring** — build the node tree above in `title_screen.tscn`, move the background/tower/vignette/logo/rule to authored textures, and strip `_build_ui` and `_build_tower_silhouette` from the script (TTL-01, TTL-02, TTL-08).
2. **Localization** — move all six strings to `strings.csv` and resolve with `tr()` (TTL-04).
3. **Version stamp** — read `application/config/version` plus `build_stamp.json` (TTL-03).
4. **Device prompt** — atlas glyph for `ui_accept`, rebuild on `symbols_invalidated` (TTL-01 support).
5. **Motion gating** — single `Tween` for parallax and pulse, skipped under `reduced_motion` (TTL-05).
6. **Transition** — `SceneTransition` autoload with a fade, used on the title-to-menu hop and reused by the loading screen (TTL-06).
7. **Save-aware framing** — returning-player subtitle and status line (TTL-07).
8. **Title theme** — `AudioDirector.play_title_theme()` and the crossfade (TTL-09).

## Data and schema changes
- New assets: `assets/ui/title_bg.png` (640×360), `assets/ui/title_tower.png` (320×360), `assets/ui/title_logo.png` (320×96), `assets/ui/title_rule.png` (240×3), `assets/shaders/vignette.gdshader`.
- New: `apps/game/client/scripts/app/scene_transition.gd`, registered as the `SceneTransition` autoload in `project.godot`.
- New: `res://build_stamp.json`, written by the export pipeline (see [`../export-tools.md`](../export-tools.md)); absence is a supported case.
- `apps/game/client/translations/strings.csv`: the `TITLE_*` keys above.
- `AudioDirector`: new `play_title_theme()` and a title music cue.
- No save-format change.

## Acceptance criteria
- [ ] `title_screen.tscn` contains the full authored node tree and `title_screen.gd` contains no `ColorRect.new()` or `Label.new()`.
- [ ] The title wordmark, tower, background, and rule are all authored textures rendered with `TEXTURE_FILTER_NEAREST`.
- [ ] `title_screen.gd` contains no non-ASCII literal.
- [ ] The vignette node sits above the background and tower and below the logo in tree order.
- [ ] The version label shows `application/config/version` and the build SHA, or `dev` when `build_stamp.json` is absent.
- [ ] Every visible string changes when the locale is switched to a stub translation.
- [ ] The prompt shows the keyboard `ui_accept` glyph with no pad connected and the pad glyph within one frame of connecting one.
- [ ] With `reduced_motion` on, `_process` creates no motion and the prompt alpha stays `1.0`.
- [ ] Advancing fades to black over `0.25` s before the main menu loads.
- [ ] With a playable save present, the subtitle and status line name the most recent warden and floor.
- [ ] With no save present, the full lore paragraph is shown.
- [ ] Advancing works from a keyboard key, a mouse button, and a gamepad button.

## Validation
Extend `apps/game/client/scripts/validation/suites/ui_suite.gd` (or add `title_suite.gd`), category `title`:

| Test id | Assertion |
|---|---|
| `title.scene_authored` | `title_screen.tscn` declares `Background`, `TowerParallax`, `Vignette`, `Logo`, `TextStack`, `Prompt`, `VersionLabel` |
| `title.no_runtime_build` | `title_screen.gd` contains no `ColorRect.new()`, `Label.new()`, or `_build_tower_silhouette` |
| `title.textures_nearest` | every `TextureRect` in the scene reports `TEXTURE_FILTER_NEAREST` and a non-null texture |
| `title.no_unicode` | `title_screen.gd` matches no non-ASCII code point |
| `title.layer_order` | `Vignette`'s index is greater than `TowerParallax`'s and less than `Logo`'s |
| `title.version_from_settings` | the label contains `ProjectSettings.get_setting("application/config/version")` |
| `title.version_fallback` | with `build_stamp.json` absent, the label ends in `dev` and no error is pushed |
| `title.localized` | every `Label` text in the scene resolves from a `strings.csv` key |
| `title.prompt_glyph_device` | simulating a pad connection changes the `PromptGlyph` atlas region |
| `title.reduced_motion` | with the flag on, no `Tween` exists after `_ready` and `PromptLabel.modulate.a == 1.0` |
| `title.transition_fade` | advancing creates a `SceneTransition` fade and changes scene only after it completes |
| `title.returning_player_copy` | with a save present, the status line contains the character name from `LocalSave.list_character_slots()` |
| `title.advance_all_devices` | a key press, a mouse press, and a joypad button press each trigger the scene change |

## Related
- Existing behavior: [`../existing_codebase/ui/title_screen.md`](../existing_codebase/ui/title_screen.md)
- Entry-flow coordination: [`title_main_continue.md`](title_main_continue.md)
- [`main_menu.md`](main_menu.md) · [`game_ui_skin.md`](game_ui_skin.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md)
- [`../pixel-style.md`](../pixel-style.md) · [`../audio-director.md`](../audio-director.md) · [`../export-tools.md`](../export-tools.md) · [`../local-save.md`](../local-save.md)
