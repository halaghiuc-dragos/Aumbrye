# Character creation

The New Warden panel: class list, mandatory name, five appearance dropdowns, and a preview. Owned by the main menu, not by `PlayerControls`.

## File
`apps/game/client/scripts/ui/character_create_ui.gd` — 211 lines, `extends Control`. No scene; instanced at `main_menu.gd:25-27`.

## Signals
| Signal | Emitted | Consumer |
|---|---|---|
| `completed(class_id, character_name, appearance)` | `:197` after validation | `main_menu.gd:176-178` → `LocalSave.queue_boot_new_game` then the loading scene |
| `cancelled` | `:202` on Back or `ui_cancel` | `main_menu.gd:181-182` restores the main panel |

## Control tree (`_build_ui`, `:42-100`)
```
Control (CharacterCreateUI, PROCESS_MODE_ALWAYS)
├── ColorRect "Backdrop"
└── PanelContainer "Panel"          (half 520 × 500)
    └── MarginContainer "Margin"
        └── VBoxContainer "ContentVBox"
            ├── Label "TitleLabel"      "Create Your Warden"
            ├── ItemList (classes, min height 120)
            ├── LineEdit (placeholder "Warden name (required)")
            ├── Label (name error, hidden, red override)
            ├── HBoxContainer "preview_row"
            │   ├── Control (140 × 200) + "Silhouette" child from GameUISkin.build_human_silhouette
            │   └── ColorRect (48 × 200) — accent swatch
            ├── HBoxContainer "Aspect"   + OptionButton (5 items)
            ├── HBoxContainer "Stature"  + OptionButton (3 items)
            ├── HBoxContainer "Build"    + OptionButton (3 items)
            ├── HBoxContainer "Head"     + OptionButton (3 items)
            ├── HBoxContainer "Trim"     + OptionButton (3 items)
            ├── Label (class detail, autowrap)
            └── HBoxContainer (Back, Begin)
```
`_add_option_row` (`:103-115`) creates each `OptionButton` with placeholder items labeled `"?"` and the caller overwrites the texts afterwards (`:70-88`).

## Data sources
| Field | Source |
|---|---|
| Class rows | `ClassCatalog.get_all_classes()` (`:142`), name-sorted (`class_catalog.gd:21-23`); five files under `content/classes/` |
| Class detail | `description` and `startingWeaponItemId` from the class JSON (`:153-156`) |
| Aspect | local `APPEARANCE_OPTIONS` mapping five labels onto `PixelDioramaStyle.PaletteTheme` values (`:13-19`) |
| Stature / Build / Head / Trim | `CharacterAppearance.HEIGHT_LABELS`, `BULK_LABELS`, `HEAD_LABELS`, `TRIM_LABELS` (`character_appearance.gd:12-20`) |
| Emitted appearance | `CharacterAppearance.profile_from_indices` (`:177-183`; `character_appearance.gd:33-46`) |

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Class selection, naming, and appearance capture | IMPLEMENTED — a valid profile reaches `LocalSave.queue_boot_new_game` | `:186-197`; `main_menu.gd:176-178` |
| Appearance preview | FAKE — the figure is six flat `ColorRect` blocks in the single constant `SILHOUETTE_COLOR`, built once at `:63` with fixed arguments `(28, 4, 1.35)`. `_on_appearance_selected` only recolors the 48 × 200 swatch, so Stature, Build, Head, and Trim change nothing on screen | `:59-68`, `:159-162`; `game_ui_skin.gd:207-231` |
| Keyboard/gamepad focus | ABSENT — `open_creation` never calls `grab_focus`, not even on the name field, so the panel is mouse-only | `:118-134`; 0 `grab_focus` matches in the file |
| Starting weapon display | PARTIAL — prints the raw content id, e.g. `Starting weapon: castle_sword`, instead of the item's display name | `:153-156`; `content/classes/knight.json:5` |
| Class information shown | PARTIAL — `statBonuses`, `allowedWeapons`, and `perk` exist in every class file and none are shown | `content/classes/knight.json:6-8`; `:153-156` |
| Name validation | PARTIAL — only `length() >= 2` after `strip_edges`; no maximum length (`max_length` is never set), no character-set restriction, and no duplicate-name check against existing characters | `:165-166`, `:186-190`; `:49-52` |
| Default selections | PARTIAL — `open_creation` hardcodes index `1` for stature, build, head, and trim rather than reading `CharacterAppearance.default_profile()` | `:129-132`; `character_appearance.gd:23-30` |
| Empty class list | PARTIAL — pressing Begin with no selectable class returns silently with no message | `:191-193` |
| Aspect naming | PARTIAL — the five aspects are the internal biome palette themes, including `"Hub ember"`, surfaced as player-facing character options | `:13-19` |
| Class art | ABSENT — the class list is an `ItemList` of plain text with no portrait, icon, or silhouette | `:45-48`, `:144-145` |
| Randomize / name suggestion | ABSENT | `:42-100` |
| Localization | ABSENT — title, placeholder, error, five row labels, `Back`, `Begin`, and the detail template are hardcoded English; the aspect labels are hardcoded in the script | `:43`, `:50`, `:54`, `:69-88`, `:96-97`, `:153-156`; 0 `tr(` calls |
| Mouse mode | PARTIAL — sets `Input.mouse_mode` directly on open and never restores it on cancel | `:134`, `:200-202` |
| Cancel ownership | PARTIAL — the panel handles `ui_cancel` in `_unhandled_input` while `main_menu.gd:208-209` returns early when it is open, so correct behavior depends on input-order between two scripts | `:205-210`; `main_menu.gd:200-219` |
| Audio | PARTIAL — button SFX come from `make_menu_button`; no confirm sting on Begin | `:93-99`; `menu_shell.gd:66-76` |

## Related
- Improvement plan: [`../actual_improvements/ui/character_create.md`](../actual_improvements/ui/character_create.md)
- [`main_menu.md`](main_menu.md) · [`continue_menu.md`](continue_menu.md) · [`title_main_continue.md`](title_main_continue.md) · [`game_ui_skin.md`](game_ui_skin.md) · [`menu_shell.md`](menu_shell.md)
- [`../character-appearance.md`](../character-appearance.md) · [`../character-service.md`](../character-service.md) · [`../content-catalog.md`](../content-catalog.md) · [`../diorama-character-skin.md`](../diorama-character-skin.md) · [`../local-save.md`](../local-save.md)
