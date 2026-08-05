# Character creation — improvement plan

## Current state
The panel captures a class, a name, and five appearance indices, and hands a valid profile to the save layer. Everything about presenting that choice is placeholder: the preview is six monochrome rectangles that never react to Stature, Build, Head, or Trim; the class rows are plain text with no art, stats, perk, or allowed weapons; the starting weapon is printed as a raw content id; nothing is focused on open, so the whole panel is mouse-only. See [`../existing_codebase/ui/character_create.md`](../existing_codebase/ui/character_create.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| CCR-01 | P0 | The appearance preview is fake. Six flat `ColorRect` blocks in one constant color, built once with fixed arguments; only a 48 × 200 accent swatch reacts to Aspect, and Stature, Build, Head, and Trim change nothing visible. The player customizes four fields blind. | `:59-68`, `:159-162`; `game_ui_skin.gd:207-231` |
| CCR-02 | P0 | Mouse-only: no `grab_focus` in `open_creation`, not even onto the name field, so the class list, five dropdowns, and both buttons are unreachable by keyboard or gamepad. | `:118-134` |
| CCR-03 | P1 | The class rows show a name and nothing else. `statBonuses`, `allowedWeapons`, and `perk` are in every class file and never surfaced, so the first irreversible decision in the game is made without data. | `content/classes/knight.json:6-8`; `:144-145`, `:153-156` |
| CCR-04 | P1 | The starting weapon is printed as a raw id: `Starting weapon: castle_sword`. | `:153-156` |
| CCR-05 | P1 | Name validation is `length >= 2` only: no maximum length, no character-set rule, no duplicate check against existing wardens. | `:165-166`, `:186-190`; no `max_length` assignment |
| CCR-06 | P1 | Zero localization, and the five Aspect labels are hardcoded in the script rather than coming from content. | `:13-19`, `:43`, `:50`, `:54`, `:69-88`, `:96-97` |
| CCR-07 | P2 | Defaults are hardcoded index `1` per row instead of `CharacterAppearance.default_profile()`. | `:129-132`; `character_appearance.gd:23-30` |
| CCR-08 | P2 | The five Aspects are internal biome palette themes, including `"Hub ember"`, presented as character identity. | `:13-19` |
| CCR-09 | P2 | Begin with an empty class list returns silently with no message. | `:191-193` |
| CCR-10 | P2 | No randomize, no name suggestion, no comparison between classes. | `:42-100` |
| CCR-11 | P2 | Sets `Input.mouse_mode` directly on open and never restores it on cancel. | `:134`, `:200-202` |
| CCR-12 | P2 | Cancel handling is split between this panel's `_unhandled_input` and an early return in the main menu, so behavior depends on input order between two scripts. | `:205-210`; `main_menu.gd:208-209` |

## Target design

### Authored scene with a live 3D preview
`scenes/ui/character_create.tscn`, three columns inside the standard modal:

```
CharacterCreate (Control)
└── PanelContainer "Panel"                 CreationPanel variation
    └── MarginContainer → HBoxContainer "Columns"
        ├── VBoxContainer "ClassColumn"      (stretch 3)
        │   ├── Label "ClassHeader"          MenuSection
        │   └── ScrollContainer → VBoxContainer "ClassCards"
        │       └── ClassCard × n           (scenes/ui/class_card.tscn)
        ├── VBoxContainer "PreviewColumn"    (stretch 4)
        │   ├── SubViewportContainer "PreviewViewport"
        │   │   └── SubViewport → WardenPreviewRig
        │   ├── HBoxContainer "PreviewControls"   rotate left / idle-pose cycle / rotate right
        │   └── Label "PreviewCaption"       class name + aspect name
        └── VBoxContainer "DetailColumn"     (stretch 3)
            ├── LineEdit "NameInput"         max_length 18
            ├── Label "NameError"            MenuError variation
            ├── Button "RandomNameButton"
            ├── VBoxContainer "AppearanceRows"
            │   └── SettingsRow-style rows: Aspect, Stature, Build, Head, Trim
            ├── PanelContainer "ClassStatsCard"
            │   └── GridContainer: stat name │ base │ delta (green/red)
            ├── Label "PerkLine"             perk name + description
            ├── Label "WeaponLine"           starting weapon display name + icon
            └── HBoxContainer "Footer"       Back │ Randomize │ Begin
```

`WardenPreviewRig` instantiates the same character skin the game uses (see [`../diorama-character-skin.md`](../diorama-character-skin.md)) inside a `SubViewport` at the pixel-diorama render scale, lit by a two-light preview setup. It applies the live profile through `CharacterAppearance.profile_from_indices`, so `height`, `bulk`, `head`, and `trim` visibly change the figure and the palette theme recolors the armor. `build_human_silhouette` is no longer used here (CCR-01).

Rejected alternative: authoring five flat portrait sprites per aspect. It would look better than rectangles but could not show stature, build, head, and trim combinations — 5 × 3 × 3 × 3 × 3 = 405 permutations.

### Class cards with real data
`class_card.tscn`:

```
ClassCard (Button, toggle_mode, focus_mode FOCUS_ALL)
├── TextureRect "Portrait"      64 × 64 from the class icon atlas
├── VBoxContainer
│   ├── Label "NameLabel"       ClassCardName
│   ├── Label "RoleLabel"       one-line role, e.g. "Frontline / Sustain"
│   └── HBoxContainer "StatPips"   armor, health, speed as 5-pip bars
└── TextureRect "SelectedMark"
```

Cards read from the class JSON, which gains `iconPath`, `role`, and `perkName`/`perkDescription`. Selecting a card populates `ClassStatsCard` with `statBonuses` rendered as `Health 100 → 120 (+20)`, `PerkLine` with the perk text, and `WeaponLine` with the starting weapon's display name and icon resolved through the item catalog rather than the raw id (CCR-03, CCR-04).

Class icons: `assets/ui/atlas/class_icons.png`, `5 × 1` grid of `64 × 64` cells, cell order `berserker, knight, rogue, scholar, sentinel`, referenced per class as `iconPath: "class_icons:knight"` — the same atlas convention as the item and status atlases (see [`status_icons_glyphs.md`](status_icons_glyphs.md)).

### Naming rules
`NameValidator.validate(name) -> {ok, reason_key}` with:
- trimmed length `2 … 18`, `max_length = 18` on the `LineEdit`;
- allowed characters letters, digits, space, apostrophe, hyphen; no leading or trailing punctuation;
- rejection of names already used by an existing character, listed from `LocalSave`;
- a shared blocked-word list under `content/text/blocked_names.json`.

`NameError` shows the localized reason and the Begin button is disabled while invalid, instead of the error appearing after the fact (CCR-05, CCR-09).

`RandomNameButton` draws from `content/text/warden_names.json` (`first`, `epithet` lists) and never produces a name that fails validation (CCR-10).

### Aspect as content, not palette enum
Aspects move to `content/appearance/aspects.json`:

```json
{ "id": "castle_iron", "nameKey": "ASPECT_CASTLE_IRON", "paletteTheme": "castle", "descKey": "ASPECT_CASTLE_IRON_DESC" }
```

with player-facing names that read as warden orders rather than biome palettes, so `"Hub ember"` disappears from character creation (CCR-06, CCR-08).

### Focus and cancel
- `initial_focus` is the previously chosen class card, else the first card.
- Focus order: class cards (vertical) → `NameInput` → `RandomNameButton` → appearance rows → `Back` → `Randomize` → `Begin`, with left/right moving between the three columns.
- Appearance rows cycle with `ui_left` / `ui_right` while focused, so a gamepad never needs to open a dropdown popup.
- `ui_page_prev` / `ui_page_next` rotate the preview.
- The panel registers with `MenuStack`, which owns `ui_cancel` and mouse mode, removing both the split cancel handling and the direct `Input.mouse_mode` write (CCR-02, CCR-11, CCR-12).

### Defaults and persistence of last choice
`open_creation` seeds every row from `CharacterAppearance.default_profile()`, then overlays the last-used creation profile stored in the meta save under `lastCreationProfile`, so a player who cancels and returns does not lose their work (CCR-07).

### Confirmation and audio
Begin plays a confirm sting through `AudioDirector` and pushes a `MenuStack.confirm` naming the class and warden name, because the choice is permanent for that character (see [`title_main_continue.md`](title_main_continue.md) for the boot handoff that follows).

## Work plan
1. **Author `character_create.tscn`** with the three-column tree above (CCR-01 support).
2. **Build `WardenPreviewRig`** and wire live profile application (CCR-01).
3. **Class cards and class JSON fields** `iconPath`, `role`, `perkName`, `perkDescription`; author `class_icons.png` (CCR-03).
4. **Stats, perk, and weapon lines** resolved through the item and class catalogs (CCR-03, CCR-04).
5. **`NameValidator`, name lists, and Begin gating** (CCR-05, CCR-09, CCR-10).
6. **Aspect content file** and localized labels (CCR-06, CCR-08).
7. **Focus graph, `MenuStack` registration, preview rotation actions** (CCR-02, CCR-11, CCR-12).
8. **Default and last-used profile seeding** (CCR-07).
9. **Confirm sting and creation confirmation**.

## Data and schema changes
- `content/classes/*.json`: new `iconPath`, `role`, `perkName`, `perkDescription`; existing `statBonuses`, `allowedWeapons`, `perk` become UI-visible.
- New `content/appearance/aspects.json`, `content/text/warden_names.json`, `content/text/blocked_names.json`.
- New `assets/ui/atlas/class_icons.png` — `5 × 1` grid, `64 × 64` cells.
- New `scenes/ui/character_create.tscn`, `scenes/ui/class_card.tscn`, `scripts/ui/warden_preview_rig.gd`, `scripts/ui/name_validator.gd`.
- Meta save: `lastCreationProfile` block.
- `strings.csv`: `CREATE_TITLE`, `CREATE_NAME_PLACEHOLDER`, `CREATE_NAME_ERR_SHORT`, `CREATE_NAME_ERR_LONG`, `CREATE_NAME_ERR_CHARS`, `CREATE_NAME_ERR_TAKEN`, `CREATE_NAME_ERR_BLOCKED`, `CREATE_ROW_ASPECT`, `CREATE_ROW_STATURE`, `CREATE_ROW_BUILD`, `CREATE_ROW_HEAD`, `CREATE_ROW_TRIM`, `CREATE_RANDOMIZE`, `CREATE_BACK`, `CREATE_BEGIN`, `CREATE_STARTING_WEAPON`, `CREATE_PERK`, `ASPECT_*`, `CLASS_ROLE_*`.

## Acceptance criteria
- [ ] Changing Stature, Build, Head, or Trim visibly changes the preview figure within one frame.
- [ ] Changing Aspect recolors the preview armor, not only a swatch.
- [ ] The preview uses the same character skin path as the in-game warden.
- [ ] Every class card shows a portrait, a role line, and stat pips; selecting one shows its stat deltas, perk text, and starting weapon display name with icon.
- [ ] No raw content id appears anywhere in the panel.
- [ ] The panel is fully operable with keyboard only and with a gamepad only, including dropdown rows without opening popups.
- [ ] Begin is disabled until the name passes validation, and the reason is shown while typing.
- [ ] Names longer than 18 characters cannot be entered; duplicate and blocked names are rejected with distinct messages.
- [ ] Randomize produces a valid name and a complete appearance every time.
- [ ] Cancelling and reopening restores the previous selections.
- [ ] `character_create_ui.gd` contains no `Input.mouse_mode` write and no `ui_cancel` handling.
- [ ] No aspect name mentions the hub or any biome.
- [ ] Switching to a stub locale changes every visible string.

## Validation
Extend `apps/game/client/scripts/validation/suites/m1_suite.gd` (character creation) and add `create` cases:

| Test id | Assertion |
|---|---|
| `create.preview_reacts_height` | setting Stature to `Tall` changes the preview rig's applied `height` and its rendered bounds |
| `create.preview_reacts_all` | each of Build, Head, Trim changes at least one preview node property |
| `create.preview_uses_game_skin` | the rig instantiates the shared character skin scene, not `build_human_silhouette` |
| `create.no_silhouette_helper` | `character_create_ui.gd` does not call `build_human_silhouette` |
| `create.class_cards_data` | every card exposes a non-null portrait texture, a role string, and stat pips |
| `create.class_json_fields` | every file in `content/classes/` has `iconPath`, `role`, `perkName`, `perkDescription`, and the `iconPath` resolves in `class_icons.png` |
| `create.weapon_display_name` | the weapon line contains the item catalog display name and not the raw id |
| `create.no_raw_ids` | no visible label text equals a known content id |
| `create.focus_on_open` | `gui_get_focus_owner()` is a class card |
| `create.focus_graph` | BFS from the initial focus reaches every card, row, and button |
| `create.rows_cycle_without_popup` | `ui_right` on a focused appearance row advances the value with no popup visible |
| `create.begin_disabled_invalid` | with a 1-character name, Begin is `disabled` and `NameError` is visible |
| `create.name_max_length` | `NameInput.max_length == 18` |
| `create.name_rules` | names failing charset, duplicate, and blocked-word rules each return their own `reason_key` |
| `create.random_name_valid` | 100 randomized names all pass validation |
| `create.reopen_restores` | cancelling after changing four rows and reopening restores those four values |
| `create.no_mouse_mode` | the script contains no `Input.mouse_mode` |
| `create.no_local_cancel` | the script contains no `ui_cancel` handling |
| `create.aspects_from_content` | the aspect list is loaded from `content/appearance/aspects.json` and no label contains `Hub` |
| `create.localized` | every visible string resolves from a `strings.csv` key |

## Related
- Existing behavior: [`../existing_codebase/ui/character_create.md`](../existing_codebase/ui/character_create.md)
- [`main_menu.md`](main_menu.md) · [`continue_menu.md`](continue_menu.md) · [`title_main_continue.md`](title_main_continue.md) · [`game_ui_skin.md`](game_ui_skin.md) · [`menu_shell.md`](menu_shell.md) · [`status_icons_glyphs.md`](status_icons_glyphs.md)
- [`../character-appearance.md`](../character-appearance.md) · [`../character-service.md`](../character-service.md) · [`../content-catalog.md`](../content-catalog.md) · [`../diorama-character-skin.md`](../diorama-character-skin.md) · [`../local-save.md`](../local-save.md)
