# Entry flow — title, main menu, continue — improvement plan

## Current state
Four scenes chain by bare `change_scene_to_file` with no transitions: title, main menu, loading screen, hub. Three of the four `.tscn` files are empty script hosts. Settings-singleton loading is duplicated across five scripts with different subsets (`title_screen.gd:14-17`, `main_menu.gd:19-22`, `settings_ui.gd:22-26`, `player_controls.gd:17-18`). Boot intent is stashed on `LocalSave` and executed a scene later. The loading screen burns a hardcoded `1.1` s before it starts working and shows three fixed strings. Because `PlayerControls` is an autoload, the inventory and talents overlays are live on the title screen. `ui_cancel` and `pause` are both bound to Escape. Nothing in the entry path focuses a control, so the flow cannot be completed on a gamepad. See [`../existing_codebase/ui/title_main_continue.md`](../existing_codebase/ui/title_main_continue.md).

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| TMC-01 | P0 | The entry path is not completable without a mouse: the main menu, continue menu, and character creator all focus nothing on open. | `main_menu.gd:69-74`, `continue_menu.gd:51-53`, `character_create_ui.gd:118-134`; 0 `grab_focus` in all three |
| TMC-02 | P0 | The global inventory and talents overlays respond to their input actions on the title screen and main menu, where there is no player and no run context. Pressing Tab on the title screen opens the stash. | `player_controls.gd:25-28` builds them as autoload children; `inventory_ui.gd:225` and `talents_ui.gd:64` have no scene or run-mode guard |
| TMC-03 | P0 | The shared settings overlay always says `"Esc: back to main menu"`, including when opened from the in-run pause menu, where Esc returns to the pause menu. | `settings_ui.gd:44`; opened from `pause_menu.gd:80-82` and from `main_menu.gd:145` |
| TMC-04 | P1 | No scene transitions anywhere in the entry path: five bare `change_scene_to_file` calls, so every hop is a hard cut. | `title_screen.gd:123`, `main_menu.gd:178`, `:189`, `loading_screen.gd:58`, `:62` |
| TMC-05 | P1 | No single boot entry point. Five scripts each load a different subset of the five settings singletons, so which settings are live depends on which screen you entered through. | `title_screen.gd:14-17` (2 of 5), `main_menu.gd:19-22` (3 of 5), `settings_ui.gd:22-26` (5 of 5), `player_controls.gd:17-18` (2 of 5) |
| TMC-06 | P1 | The loading screen awaits a hardcoded `1.1` s *before* doing any work, then does the work synchronously, so entry always costs at least `1.1` s plus load time and the "loading" period is mostly a fixed delay. | `loading_screen.gd:7`, `:51-54` |
| TMC-07 | P1 | Loading progress is three hardcoded strings with no progress bar and no real progress source; a slow boot looks identical to a hung one. | `loading_screen.gd:41`, `:52`, `:60` |
| TMC-08 | P1 | A boot failure shows a message for `1.2` s on the screen that is about to be destroyed, then the main menu appears with no record of what failed. | `loading_screen.gd:55-59`; `main_menu.gd:17-35` reads no failure state |
| TMC-09 | P1 | Three of the four entry scenes are empty script hosts, so the entry path cannot be art-directed or previewed in the editor. | `title_screen.tscn`, `main_menu.tscn`, `loading_screen.tscn` are 13 lines each with one node |
| TMC-10 | P2 | `ui_cancel` and `pause` are both bound to Escape, and precedence between the ten handlers that check them depends on `_input` versus `_unhandled_input` and on tree order. | `project.godot:91` and `:188` both `4194305`; `main_menu.gd:200` uses `_input` |
| TMC-11 | P2 | Both the title screen and the main menu call `AudioDirector.play_menu_music()`, re-triggering the track across the transition. | `title_screen.gd:17`, `main_menu.gd:22` |
| TMC-12 | P2 | Boot is not cancellable: once the loading screen starts there is no back affordance. | `loading_screen.gd:47-62` |
| TMC-13 | P2 | `LocalSave.queue_boot_continue_backup` has no caller; the settings restore path calls `restore_backup` directly, so one of the two boot modes is unreachable. | `local_save.gd:190-192`; `settings_ui.gd:405` |

## Target design

### One boot service
New `apps/game/client/scripts/app/boot_service.gd`, autoloaded as `BootService`, is the only place settings singletons are loaded and applied:

```gdscript
func boot_client() -> void        # called once from _ready of the autoload
func reload_all_settings() -> void
signal settings_reloaded
```

`boot_client()` loads `AccessibilitySettings`, `AudioSettings`, `PixelDioramaSettings`, `LeaderboardSettings`, applies `DisplaySettings`, and primes `PixelDioramaBootstrap`, in that fixed order. The four call sites in `title_screen.gd`, `main_menu.gd`, `settings_ui.gd`, and `player_controls.gd` are deleted; `settings_ui.gd` calls `reload_all_settings()` only when it needs a re-read (TMC-05).

Rejected alternative: leaving each screen to load what it needs. That is the current design, and it is why the pixel-diorama settings are only guaranteed loaded if the player has opened the settings panel.

### Scene transitions
New `apps/game/client/scripts/app/scene_transition.gd`, autoloaded as `SceneTransition` on a `CanvasLayer` at layer `100`:

```gdscript
func change_scene(path: String, fade_out := 0.25, fade_in := 0.20) -> void
func change_scene_with_progress(path: String) -> void   # ResourceLoader.load_threaded_request
signal progress(ratio: float)
```

Every `change_scene_to_file` in the UI layer routes through it. `change_scene_with_progress` uses `ResourceLoader.load_threaded_get_status` so the loading screen has a real progress ratio (TMC-04, TMC-07).

Fades are skipped when `AccessibilitySettings.reduced_motion` is on; the scene change still goes through `SceneTransition` so there is one code path.

### Loading screen with real progress
```
LoadingScreen (Control, FULL_RECT)
├── TextureRect "Background"      # assets/ui/title_bg.png, dimmed
├── MenuModal   "Panel"           # half 320 × 140, no title
│   └── ContentVBox
│       ├── Label "PhaseLabel"          BodyText — localized phase name
│       ├── ProgressBar "ProgressBar"   ResourceBar variation, 0-1
│       └── Label "TipLabel"            HintText — rotating gameplay tip from content
└── Button "CancelButton"          # PRESET_BOTTOM_RIGHT, visible only before execute_boot begins
```

`MIN_DISPLAY_SEC` drops to `0.35` s and is applied as a *minimum total* rather than a leading await, so a fast boot no longer waits `1.1` s and a slow boot shows real motion. Phases: `LOADING_PHASE_SAVE`, `LOADING_PHASE_CONTENT`, `LOADING_PHASE_SCENE`, each pushing a `progress` ratio (TMC-06, TMC-07, TMC-09).

`CancelButton` is enabled until `LocalSave.execute_boot()` is entered; pressing it returns to the main menu with no state change (TMC-12).

### Boot failure carried forward
`LocalSave.execute_boot()` returns a result dictionary instead of a bool:

```gdscript
{ "ok": bool, "reason": StringName, "detail": String, "recoverable": bool }
```

On failure, `SceneTransition` carries it to the main menu, which opens a `MenuStack.confirm`-style notice naming the reason, with a Restore Backup action when `recoverable` is true, wired to the shared restore panel from [`continue_menu.md`](continue_menu.md). `queue_boot_continue_backup` becomes the path that restore uses, so the dead boot mode is exercised (TMC-08, TMC-13).

### Front-end overlay gating
`PlayerControls` gains a context gate:

```gdscript
enum Context { FRONT_END, HUB, RUN }
func current_context() -> Context
func allows_player_ui() -> bool     # false in FRONT_END
```

Context is derived from the current scene's group membership — front-end scenes join a new `front_end` group — and refreshed on `scene_changed`, which `player_controls.gd:47-56` already hooks. `inventory_ui.gd`, `talents_ui.gd`, `loadout_ui.gd`, and the quick-slot polling at `player_controls.gd:154-164` all early-return when `allows_player_ui()` is false. The pause menu stays available in `HUB` and `RUN` only (TMC-02).

### Settings overlay knows its caller
`open_settings(return_context: StringName)` records who opened it, and the hint row resolves to `SET_HINT_BACK_MENU`, `SET_HINT_BACK_PAUSE`, or `SET_HINT_BACK_HUB` accordingly. `close_settings` returns focus to the opener's `initial_focus` through `MenuStack` (TMC-03).

### Escape disambiguation
`pause` keeps Escape and pad button 6; `ui_cancel` keeps Escape and pad button 1. `MenuStack` claims `ui_cancel` whenever `depth() > 0` and marks it handled, so `pause` only reaches `PlayerControls` when no modal is open. `main_menu.gd`'s `_input` override is deleted. A validation test asserts exactly one script matches `is_action_pressed("ui_cancel")` under `scripts/ui/` (TMC-10).

### Music continuity
`AudioDirector.play_menu_music()` becomes idempotent: it returns early when the requested track is already playing, so the title-to-menu hop does not restart it, and the title's own theme crossfades once (TMC-11).

### Focus across the flow
Per-screen `initial_focus` values are listed in [`menu_shell_a11y.md`](menu_shell_a11y.md). The entry-flow requirement is that every hop lands focus somewhere: title (no controls, any-input advance), main menu (Continue or New Game), continue menu (most recent slot card), character creator (class list), loading screen (Cancel while it exists, otherwise nothing focusable is required) (TMC-01).

## Work plan
1. **Focus across the flow** — the three menus grab focus on open (executed in [`main_menu.md`](main_menu.md), [`continue_menu.md`](continue_menu.md), [`character_create.md`](character_create.md)) (TMC-01).
2. **Front-end gating** — `front_end` group, `PlayerControls.allows_player_ui()`, early returns in the four overlay scripts (TMC-02).
3. **Settings return context** — `open_settings(return_context)` and the three hint keys (TMC-03).
4. **`BootService`** — one autoload owning settings load and apply; delete the four duplicated blocks (TMC-05).
5. **`SceneTransition`** — fades plus threaded loading; route all five `change_scene_to_file` calls through it (TMC-04).
6. **Loading screen rework** — real progress, phases, tips, cancel, `0.35` s minimum total (TMC-06, TMC-07, TMC-09, TMC-12).
7. **Boot result plumbing** — result dictionary, failure notice on the main menu, restore path through `queue_boot_continue_backup` (TMC-08, TMC-13).
8. **Escape ownership and idempotent music** (TMC-10, TMC-11).

## Data and schema changes
- New autoloads in `project.godot`: `BootService`, `SceneTransition` (and `MenuStack` from [`menu_shell.md`](menu_shell.md)).
- `LocalSave.execute_boot()` returns a dictionary; `queue_boot_continue_backup` gains a caller.
- Front-end scenes join the `front_end` group: `title_screen.tscn`, `main_menu.tscn`, `loading_screen.tscn`.
- New: `content/ui/loading_tips.json` plus `content/schemas/loading-tips.v1.json` (`tips[] { key, minFloor }`).
- `apps/game/client/translations/strings.csv`: `LOADING_PHASE_SAVE`, `LOADING_PHASE_CONTENT`, `LOADING_PHASE_SCENE`, `LOADING_CANCEL`, `LOADING_TIP_*`, `BOOT_FAIL_TITLE`, `BOOT_FAIL_*` per reason, `SET_HINT_BACK_MENU`, `SET_HINT_BACK_PAUSE`, `SET_HINT_BACK_HUB`.
- No save-format change from this plan on its own.

## Acceptance criteria
- [ ] The full entry path — title, main menu, new character, loading, hub — is completable with a gamepad only.
- [ ] Pressing the `inventory` or `talents` action on the title screen or main menu opens nothing.
- [ ] Quick-slot actions do nothing in the front end.
- [ ] Settings opened from the pause menu shows a back-to-pause hint; opened from the main menu it shows back-to-menu.
- [ ] Closing settings returns focus to the control that opened it.
- [ ] Exactly one script loads each settings singleton, and it is `boot_service.gd`.
- [ ] `title_screen.gd`, `main_menu.gd`, `settings_ui.gd`, and `player_controls.gd` contain no `load_from_save()` call.
- [ ] No UI script calls `change_scene_to_file` directly.
- [ ] Every scene hop in the entry path fades out and in, unless `reduced_motion` is on.
- [ ] A boot that completes in under `0.35` s still shows the loading screen for `0.35` s total, and no boot waits `1.1` s before starting work.
- [ ] The loading progress bar advances monotonically from a real `ResourceLoader` ratio.
- [ ] A simulated corrupt save produces a named failure notice on the main menu with a working Restore Backup action.
- [ ] Restoring from that notice goes through `queue_boot_continue_backup` and boots the restored save.
- [ ] Cancelling on the loading screen before boot starts returns to the main menu with the roster unchanged.
- [ ] Only `menu_stack.gd` handles `ui_cancel` under `scripts/ui/`.
- [ ] Advancing from the title screen does not restart the menu music.

## Validation
New suite `apps/game/client/scripts/validation/suites/entry_flow_suite.gd`, category `entry_flow`:

| Test id | Assertion |
|---|---|
| `entry_flow.pad_only_path` | a scripted gamepad-only sequence reaches the hub from the title screen |
| `entry_flow.focus_each_hop` | after each hop, the focus owner is inside the newly presented modal (or the screen has no focusable control) |
| `entry_flow.front_end_gate` | with the current scene in the `front_end` group, the `inventory` and `talents` actions leave both overlays closed |
| `entry_flow.quick_slots_gated` | quick-slot actions in the front end call no `InventoryService.activate_quick_slot` |
| `entry_flow.settings_return_hint` | the hint key differs between the pause-menu and main-menu callers |
| `entry_flow.settings_focus_return` | closing settings restores the opener's focus owner |
| `entry_flow.single_settings_loader` | only `boot_service.gd` matches `load_from_save()` outside the settings singletons themselves |
| `entry_flow.no_direct_scene_change` | no file under `scripts/ui/` matches `change_scene_to_file` |
| `entry_flow.transition_used` | each hop creates a `SceneTransition` fade, and none is created with `reduced_motion` on |
| `entry_flow.loading_min_total` | a boot that finishes instantly still displays the loading screen for `>= 0.35` s and `< 0.6` s |
| `entry_flow.loading_progress_monotonic` | the progress bar value never decreases and reaches `1.0` |
| `entry_flow.boot_failure_notice` | a corrupt save yields a main-menu notice whose body contains the failure reason key |
| `entry_flow.boot_failure_restore` | the notice's restore action calls `queue_boot_continue_backup` and boots successfully |
| `entry_flow.loading_cancel` | cancelling before `execute_boot` returns to the main menu and leaves `list_character_slots()` unchanged |
| `entry_flow.single_cancel_handler` | exactly one script under `scripts/ui/` matches `is_action_pressed("ui_cancel")` |
| `entry_flow.music_not_restarted` | advancing from the title screen leaves the menu music playback position increasing, not reset to 0 |

## Related
- Existing behavior: [`../existing_codebase/ui/title_main_continue.md`](../existing_codebase/ui/title_main_continue.md)
- Per-screen plans: [`title_screen.md`](title_screen.md) · [`main_menu.md`](main_menu.md) · [`continue_menu.md`](continue_menu.md) · [`character_create.md`](character_create.md) · [`run_outcome.md`](run_outcome.md) · [`run_flow_ui.md`](run_flow_ui.md)
- [`menu_shell.md`](menu_shell.md) · [`menu_shell_a11y.md`](menu_shell_a11y.md) · [`settings.md`](settings.md)
- [`../local-save.md`](../local-save.md) · [`../run-flow.md`](../run-flow.md) · [`../player-controls.md`](../player-controls.md) · [`../project-config-autoloads.md`](../project-config-autoloads.md)
