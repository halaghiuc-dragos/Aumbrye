# Display settings

A twelve-line static helper that applies one accessibility field — `ui_scale` — to the root viewport. Despite the name it does not touch window mode, resolution, vsync, or any other display property.

## File
`apps/game/client/scripts/ui/display_settings.gd` — 12 lines, `extends RefCounted`, `class_name DisplaySettings`. Not an autoload (`project.godot:28-53` lists no `DisplaySettings` entry); reached through its global class name.

Whole implementation:

```gdscript
static func apply() -> void:
    var tree := Engine.get_main_loop() as SceneTree
    if tree == null or tree.root == null:
        return
    tree.root.content_scale_factor = clampf(AccessibilitySettings.ui_scale, 0.75, 1.75)
```

## Call sites
| Caller | When |
|---|---|
| `title_screen.gd:15` | boot |
| `main_menu.gd:20` | main-menu entry |
| `player_controls.gd:18` | autoload `_ready` |
| `settings_ui.gd:23` | settings overlay `_ready` |
| `settings_ui.gd:77` | on every UI-scale slider step |

Four of the five calls are startup calls that repeat the same work (see [`title_main_continue.md`](title_main_continue.md)).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Applies `ui_scale` to `root.content_scale_factor` | IMPLEMENTED | `:11` |
| Effect under the project's stretch configuration | PARTIAL — the project uses `window/stretch/mode="canvas_items"` with `window/stretch/scale_mode="integer"`, which rounds the final stretch scale down to a whole number. A `content_scale_factor` between `1.05` and `1.5` on a window at the `1920 x 1080` base size therefore has no guaranteed effect. Not confirmed at runtime; recorded as a risk with the project settings as evidence | `project.godot:57-60`; `:11` |
| Clamp range vs. slider range | PARTIAL — the helper clamps to `0.75 … 1.75` while the only control that feeds it ranges `0.80 … 1.50`, so the clamp can never engage and the two ranges are independent constants | `:11`; `settings_ui.gd:70-72` |
| Anything other than UI scale | ABSENT — no window mode, borderless, monitor selection, vsync, frame cap, resolution, or aspect handling anywhere in the file or elsewhere in `scripts/ui/` | `:7-11`; 0 `DisplayServer.window_set_mode` matches under `scripts/ui/` |
| Layout response to scale changes | ABSENT — nothing re-runs layout for code-built panels after a scale change; panels that cached a half-size keep it | `:7-11`; e.g. `settings_ui.gd:518-531` recentres only on open |
| Signal or notification on change | ABSENT — callers must remember to call `apply()`; there is no `changed` signal on `AccessibilitySettings` | `accessibility_settings.gd:1-35` |
| File placement and name | PARTIAL — a non-UI static helper living in `scripts/ui/`, named for a domain it does not cover | `:1-11` |

## Related
- Improvement plan: [`../actual_improvements/ui/display_settings.md`](../actual_improvements/ui/display_settings.md)
- [`settings.md`](settings.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`title_main_continue.md`](title_main_continue.md)
- [`../accessibility.md`](../accessibility.md) · [`../pixel-diorama-settings.md`](../pixel-diorama-settings.md) · [`../project-config-autoloads.md`](../project-config-autoloads.md)
