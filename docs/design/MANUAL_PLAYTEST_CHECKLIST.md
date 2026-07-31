# Manual playtest checklist (living document)

> **Single source of truth** for all human playtest and feel gates across M0–M7.  
> **Do not create per-phase playtest checklists** — add items here under the correct section as each milestone ships.

**Tester:** _____________  
**Date:** _____________  
**Build / commit:** _____________

---

## Before any manual sign-off

1. Run automated validation — must pass with **0 failures**:

```powershell
./scripts/run-all-validation.ps1
```

2. Review report: `reports/validation-summary.json` and [VALIDATION_PLATFORM.md](VALIDATION_PLATFORM.md) for automated coverage.

Manual items below cover **feel, UX, and integration paths** that automation cannot judge.

### Automated coverage map (reference test IDs)

| Area | Automated | Test IDs (sample) |
| ---- | --------- | ----------------- |
| Kill enemies stay dead | Yes | `enemy.dies_at_zero_hp`, `enemy.no_stagger_revive` |
| Dungeon build / loot / enemies | Yes | `dungeon.rooms_instantiated`, `dungeon.loot_placed` |
| Offline procgen default | Yes | `procgen.offline_no_api_in_run_flow`, `m5.net.online_path_optional` |
| Three biomes procgen + build | Yes | `m5.procgen.*`, `m5.dungeon.*` |
| Six damage types + resist | Yes | `m5.damage.six_types`, `m5.damage.resistance_pipeline` |
| Five statuses + HUD wiring | Yes | `m5.status.five_definitions`, `m5.status.hud_icon_row` |
| Five weapon archetypes (data) | Yes | `m5.weapon.*_json`, `m5.loadout.*` |
| Theme enemies + bosses (data) | Yes | `m5.enemy.*`, `m5.boss.theme_scenes` |
| Per-biome audio profiles | Yes | `m5.audio.profile_*`, `m5.audio.set_biome` |
| Save integer normalization | Yes | `m5.save.integer_normalization` |
| Epic+ affix counts | Yes | `m5.loot.epic_affix_counts`, C# `AffixRollerTests` |
| Hub M4 services | Yes | `hub_m4.*` suite |
| M4 progression / inventory | Yes | `progression.*`, `inventory.*` |
| M6 biomes (frozen, cathedral) | Yes | `m6.biome.*`, `m6.procgen.*`, `m6.dungeon.*` |
| M6 enemy/boss scenes | Yes | `m6.scene.*`, `m6.boss.m6_theme_scenes` |
| M6 room preloads | Yes | `m6.rooms.*_load` |
| M6 achievements + a11y | Yes | `m6.achievements.*`, `m6.a11y.*` |

---

## M1 — Combat arena (KB/M signed off 2026-07-29)

Historical record: [M1_PLAYTEST_CHECKLIST.md](M1_PLAYTEST_CHECKLIST.md) (archived).

| ID | Item | Status |
|----|------|--------|
| M1.kbm.core_loop | WASD, mouse look, sprint, jump, dodge, LMB/RMB, parry/block, lock-on, hitboxes, dummy kill, **R** reset | [x] |
| M1.kbm.win_strategies | Roll / parry / spacing strategies vs training grunt | [x] |

### M1 carry-over → M7 (gamepad)

| ID | Item | Status |
|----|------|--------|
| M7.gamepad.arena_full_loop | Full combat arena duel completable gamepad-only (no mouse/KB) | [ ] |
| M7.gamepad.lock_on_switch | Lock-on + target switch (right stick while locked) | [ ] |
| M7.gamepad.hub_castle_loop | Full hub → castle → escape loop on gamepad | [ ] |

Bindings exist in `project.godot`; verify when controller hardware available.

---

## M2 — Vertical slice (signed off 2026-07-30)

Historical record: [M2_IMPLEMENTATION_LOG.md](M2_IMPLEMENTATION_LOG.md).

| ID | Item | Status |
|----|------|--------|
| M2.kbm.castle_loop | Hand-authored castle slice: combat, loot, boss, escape, hub return | [x] |

### M2 carry-over → later phases

| ID | Item | Target | Status |
|----|------|--------|--------|
| M2.deferred.external_playtest | Optional friend playtest feedback | M7 (`SHIP-7.1`) | [ ] |
| M2.deferred.castle_art | Blockout accepted; art pass when final assets land | M6 | [ ] |
| M2.deferred.corrupt_save_manual | Bad JSON → fresh start + starter sword (feel/UX) | M7 | [ ] |

---

## M3 — Server generation (closed 2026-07-30)

Implementation record: [M3_IMPLEMENTATION_LOG.md](M3_IMPLEMENTATION_LOG.md).  
**Structural M3 acceptance criteria are automated** (`procgen_suite`, C# procgen tests). Manual items below are spot-checks automation cannot replace.

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M3.automated | Procgen determinism, CLI JSON strip, dungeon build, offline default | [x] | `./scripts/run-all-validation.ps1` |
| M3.seed.spot_check | Enter seed `42001` twice → identical room layout in-game | [ ] | F1 shows seed; compare room positions |
| M3.procgen_cli.runtime | `dotnet build tools/procgen-cli/ProcgenCli.csproj` then hub new run works | [ ] | Clear error if CLI missing |
| M3.offline.play_session | API stopped / no internet → new run + continue playable, no hang | [ ] | Also `M7.offline.no_hang` |
| M3.cross_machine.seed | Same seed + build + `content/` → identical layout on two machines | [ ] | Optional if second PC available |

### M3 carry-over → M7 (feel polish)

| ID | Item | Status |
|----|------|--------|
| M7.movement.feel | Walk full procgen run — rooms connect, no falling off map | [ ] |
| M7.movement.boss_path | Boss path reachable from entrance without soft-lock | [ ] |
| M7.combat.hp_bar_visual | HP bars: black bar, red depletes R→L, occluded by walls, gone on death | [ ] |
| M7.combat.shield_feel | Shield-bearer frontal block feels right in live combat | [ ] |
| M7.loot.interact_feel | Open chests with **E** — items appear in inventory grid | [ ] |
| M7.traps.damage_feel | Traps damage the player | [ ] |
| M7.boss.door_flow | Boss door: **E** open → cross threshold → door seals | [ ] |
| M7.results.escape_flow | Final boss defeated (floor 10) → exit portal → results → hub | [ ] |
| M7.camera.toggle_feel | **P** toggles 1P/3P; F1 shows `camera: 1P` or `3P` | [ ] |
| M7.camera.relaunch_persistence | Camera preference persists after quit/relaunch | [ ] |
| M7.lock_on.fp_readability | Lock reticle readable in first person | [ ] |
| M7.hub.interaction_feel | **E** at portal; **Esc** closes; seed **Back** returns; invalid seed feedback | [ ] |
| M7.continue.full_playthrough | Mid-run quit restore; boss-room quit; death disables Continue; complete disables Continue | [ ] |
| M7.debug.overlay_runtime | F1 shows entered seed during run; cleared after hub return | [ ] |
| M7.arena.combat_feel | Hub arena: hit, stagger, parry/block, grunt death, **R** reset | [ ] |
| M7.procgen_cli.missing_ux | Procgen-cli missing → hub shows clear error | [ ] |

---

## M4 — Gameplay loop (closed 2026-07-30)

Close record: [M4_IMPLEMENTATION_LOG.md](M4_IMPLEMENTATION_LOG.md). Automated validation covers hub services, affixes, XP/talents, relics, inventory UX, cloud save API, economy (`hub_m4_suite`, `progression_suite`, `inventory_suite`).

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M4.automated | Full gameplay loop structural coverage | [x] | `./scripts/run-all-validation.ps1` |
| M4.TEST-4.1 | Ten consecutive runs — no softlock; notes in [m4_soak_notes.md](m4_soak_notes.md) | [ ] | Soak gate before M6 content volume |
| M4.cloud_e2e | Cloud save round-trip on second device/session with API running | [ ] | Also M7 `STEAM-7.3` |
| M2.deferred.corrupt_save_manual | Bad JSON → fresh start + starter sword (optional spot-check) | [ ] | |

### M4 carry-over → later phases

| ID | Item | Target | Status |
|----|------|--------|--------|
| M4.deferred.gamepad_loop | Gamepad-only hub → castle → escape | M7 `POLISH-7.1` | [ ] |

---

## M5 — Content pack A (closed 2026-07-30)

Automated validation covers biomes, procgen, combat depth, weapons, bosses, loot, audio profiles (`m5_suite` + C# theme tests). **Prerequisite:** `./scripts/run-all-validation.ps1` passes with 0 failures.

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M5.automated | All M5 structural milestones | [x] | `m5_suite` + C# `M5BiomeGeneratorTests` |
| M5.biome.e2e | Complete a full run in **each** biome (castle, crystal, swamp) → boss → escape | [ ] | Portal biome buttons |
| M5.weapons.feel | Hub **Tab** loadout — try greatsword, dagger, spear, bow vs arena grunt | [ ] | Unlock spear Lv5+, bow Lv8+ |
| M5.status.feel | Burn/bleed/poison/freeze/stun readable in combat; F8 debug burn works | [ ] | Swamp poison pools fair |
| M5.boss.crystal | Crystal Sovereign fight — phase telegraphs, winnable | [ ] | Miniboss guardian optional |
| M5.boss.swamp | Swamp Hydra fight — poison cleanse zones, winnable | [ ] | Miniboss hag optional |
| M5.audio.crossfade | Each biome ambience distinct; boss music crossfades cleanly | [ ] | Generator-tone stubs OK for M5 |
| M5.theme.blind | Blind playtester names theme without UI label (spot check) | [ ] | Silhouette/lighting/audio only |

### M5 carry-over → M6/M7

| ID | Item | Target | Status |
|----|------|--------|--------|
| M5.deferred.final_art | Pixel-diorama room art, OGG audio, status icons | M6/M7 | [ ] |
| M5.deferred.mythic_uniques | Per-item Mythic unique rules | M6 | [ ] |
| M5.deferred.item_roster | Full ~80-item roster | M6 `ITEM-6.1` | [ ] |
| M5.deferred.online_default | Enable online procgen when API stable | M7 | [ ] |

---

## M6 — Content pack B

Close record: [M6_IMPLEMENTATION_LOG.md](M6_IMPLEMENTATION_LOG.md). Printable mirror: [M6_MANUAL_PLAYTEST_CHECKLIST.md](M6_MANUAL_PLAYTEST_CHECKLIST.md) (content canonical here).

**Automated:** ✅ `m6_suite` (73 tests) + full validation (363 Godot, 83 backend). **Scene fix:** UTF-8 BOM stripped from 54 M6 `.tscn`/`.gd` files.

**Scope:** Frozen Fortress + Dark Cathedral themes; EA roster complete (5 themes, 20 enemies, 8 bosses, 79 items); achievements + leaderboards; website pages; accessibility baseline; enemy pooling.

### Prerequisites

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.automated | Biomes, procgen, dungeon build, enemy/boss scenes, room preloads, achievements, a11y | [x] | `./scripts/run-all-validation.ps1` — 0 failures |
| M6.prereq.backend | Backend API running for account + leaderboards tests | [ ] | `dotnet run --project services/backend/src/Aumbrye.Api` |
| M6.prereq.web | Web dev server running for website tests | [ ] | `npm run dev` in `apps/web/`; set `VITE_API_URL` |
| M6.prereq.godot | Godot client opens hub without parse errors | [ ] | Main scene `scenes/hub/hub.tscn`; F5 from editor |

### Summary gates (roll-up)

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.theme.frozen | Frozen Fortress — generate + clear | [ ] | See **Frozen Fortress** subsection |
| M6.theme.cathedral | Dark Cathedral — generate + clear | [ ] | See **Dark Cathedral** subsection |
| M6.enemy.roster | 20-enemy roster combat sanity | [ ] | See **Enemy roster** subsection |
| M6.boss.all_eight | All 8 bosses readable + clearable | [ ] | See **Boss spot-check** subsection |
| M6.meta.achievements | Achievement unlock + toast on escape | [ ] | See **Achievements** subsection |
| M6.meta.leaderboards | Web leaderboards match API | [ ] | See **Leaderboards** subsection |
| M6.web.account | Register/login against local API | [ ] | See **Website** subsection |
| M6.a11y.settings | UI scale + reduce shake in settings | [ ] | See **Accessibility** subsection |
| M6.perf.smoke | 1080p combat room frame time spot-check | [ ] | See **Performance** subsection |

### Frozen Fortress (THEME-6.1)

Hub → **E** at Frozen Fortress portal → new run (custom seed optional, e.g. `42001`).

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.theme.frozen_portal | Hub portal starts frozen_fortress run | [ ] | Biome label readable; no hang |
| M6.theme.frozen_procgen | Rooms connect; no void falls; boss path reachable | [ ] | F1 shows seed; `frozen_*` room templates |
| M6.theme.frozen_identity | Ice/snow lighting + materials read as Frozen Fortress | [ ] | Distinct from castle/crystal/swamp |
| M6.theme.frozen_enemies | Frost raider, archer, knight, hound spawn and fight | [ ] | Telegraphs readable; no instant-hit spam |
| M6.theme.frozen_freeze | Freeze status applies and is readable in combat | [ ] | HUD status row; `freeze_master` achievement path |
| M6.theme.frozen_traps | Frost hazards damage player fairly | [ ] | Telegraph before damage |
| M6.theme.frozen_loot | Chests open with **E**; items enter inventory | [ ] | Theme loot table active |
| M6.theme.frozen_boss | `boss_frost_warlord` — phases telegraphed, winnable | [ ] | Boss door **E** → seal → fight |
| M6.theme.frozen_escape | Defeat boss → exit portal → results → hub | [ ] | XP/gold update; `frozen_clear` achievement |
| M6.theme.frozen_continue | Mid-run quit → Continue restores frozen run | [ ] | Same biome, room, inventory |

### Dark Cathedral (THEME-6.2)

Hub → **E** at Dark Cathedral portal → new run.

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.theme.cathedral_portal | Hub portal starts dark_cathedral run | [ ] | Biome label readable |
| M6.theme.cathedral_procgen | Rooms connect; puzzle/secret rooms appear | [ ] | `cathedral_*` templates; vertical layouts OK |
| M6.theme.cathedral_vertical | Stairs/hall height changes navigable | [ ] | No camera clipping through floors |
| M6.theme.cathedral_lighting | Gothic purple/shadow lighting identity | [ ] | Distinct from frozen and castle |
| M6.theme.cathedral_enemies | Acolyte, warden, shade spawn and fight | [ ] | Shade teleport harass fair |
| M6.theme.cathedral_loot | Chests + theme uniques obtainable | [ ] | Shadow/holy item names in loot |
| M6.theme.cathedral_boss | `boss_cathedral_hollow` — phases telegraphed, winnable | [ ] | No unavoidable instant kill |
| M6.theme.cathedral_miniboss | `miniboss_cathedral_bell` (optional arena room) | [ ] | Optional if seed places miniboss |
| M6.theme.cathedral_escape | Escape → results → hub; `cathedral_clear` unlocks | [ ] | Achievement toast on first clear |

### Boss spot-check (all 8 EA bosses)

Complete at least one full clear per boss across any biome run. Minibosses count toward roster but need not block M6 sign-off if optional rooms skipped.

| ID | Boss ID | Theme | Status | Notes |
|----|---------|-------|--------|-------|
| M6.boss.castle_knight | `boss_castle_knight` | Forgotten Castle | [ ] | M2 baseline; re-verify after M6 volume |
| M6.boss.castle_captain | `miniboss_castle_captain` | Forgotten Castle | [ ] | Miniboss |
| M6.boss.crystal_sovereign | `boss_crystal_sovereign` | Crystal Caverns | [ ] | Phase transitions readable |
| M6.boss.crystal_guardian | `miniboss_crystal_guardian` | Crystal Caverns | [ ] | Miniboss |
| M6.boss.swamp_devourer | `boss_swamp_devourer` | Poison Swamp | [ ] | Poison zones fair |
| M6.boss.frost_warlord | `boss_frost_warlord` | Frozen Fortress | [ ] | M6 new |
| M6.boss.cathedral_hollow | `boss_cathedral_hollow` | Dark Cathedral | [ ] | M6 new |
| M6.boss.cathedral_bell | `miniboss_cathedral_bell` | Dark Cathedral | [ ] | M6 new miniboss |

### Enemy roster sanity (20 EA enemies)

Spot-check each enemy in live combat (arena or dungeon). Focus on M5 gap fills + M6 additions if time-limited.

| ID | Enemy ID | Theme | Status | Notes |
|----|----------|-------|--------|-------|
| M6.enemy.castle_hound | `castle_hound` | Castle | [ ] | M5 gap fill |
| M6.enemy.crystal_crawler | `crystal_crawler` | Crystal | [ ] | M5 gap fill |
| M6.enemy.crystal_spitter | `crystal_spitter` | Crystal | [ ] | M5 gap fill |
| M6.enemy.crystal_wisp | `crystal_wisp` | Crystal | [ ] | M5 gap fill |
| M6.enemy.swamp_slasher | `swamp_slasher` | Swamp | [ ] | M5 gap fill |
| M6.enemy.swamp_spitter | `swamp_spitter` | Swamp | [ ] | M5 gap fill |
| M6.enemy.swamp_brute | `swamp_brute` | Swamp | [ ] | M5 gap fill |
| M6.enemy.swamp_swarm | `swamp_swarm` | Swamp | [ ] | M5 gap fill |
| M6.enemy.frost_raider | `frost_raider` | Frozen | [ ] | M6 |
| M6.enemy.frost_archer | `frost_archer` | Frozen | [ ] | M6 |
| M6.enemy.frost_knight | `frost_knight` | Frozen | [ ] | M6 elite |
| M6.enemy.frost_hound | `frost_hound` | Frozen | [ ] | M6 fast |
| M6.enemy.cathedral_acolyte | `cathedral_acolyte` | Cathedral | [ ] | M6 caster |
| M6.enemy.cathedral_warden | `cathedral_warden` | Cathedral | [ ] | M6 melee |
| M6.enemy.cathedral_shade | `cathedral_shade` | Cathedral | [ ] | M6 teleport |

### Items and loot (ITEM-6.1)

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.items.catalog_breadth | Multiple rarities drop across a full run | [ ] | Common → rare+ visible in inventory |
| M6.items.epic_affix | Epic+ items show expanded affix names | [ ] | Affix pool expansion from M6 |
| M6.items.frost_ice_ring | `frost_ice_ring` obtainable (frozen loot) | [ ] | Theme unique |
| M6.items.frost_warlord_blade | `frost_warlord_blade` obtainable | [ ] | Theme unique |
| M6.items.frost_raider_boots | `frost_raider_boots` obtainable | [ ] | Theme unique |
| M6.items.cathedral_holy_charm | `cathedral_holy_charm` obtainable | [ ] | Theme unique |
| M6.items.cathedral_shadow_dagger | `cathedral_shadow_dagger` obtainable | [ ] | Theme unique |
| M6.items.cathedral_warden_helm | `cathedral_warden_helm` obtainable | [ ] | Theme unique |
| M6.items.equip_apply | Equipped theme uniques change stats in HUD | [ ] | Compare before/after in inventory |

### Achievements (META-6.1)

Requires escape or in-run triggers. Toast UI: `achievement_toast.tscn`.

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.meta.achievement_toast | Toast appears bottom-right on unlock | [ ] | Readable title + description |
| M6.meta.achievement_frozen_clear | `frozen_clear` (Frostbreaker) unlocks on frozen escape | [ ] | First frozen full clear |
| M6.meta.achievement_cathedral_clear | `cathedral_clear` (Hollow Light) unlocks on cathedral escape | [ ] | First cathedral full clear |
| M6.meta.achievement_all_biomes | `all_biomes` (World Walker) after 5th biome clear | [ ] | Requires all EA biomes |
| M6.meta.achievement_leaderboard | `leaderboard_submit` (On the Board) on opt-in submit | [ ] | Tied to leaderboard flow |
| M6.meta.achievement_persist | Unlocked achievements persist after hub return + relaunch | [ ] | Check save / local meta |

### Leaderboards (META-6.2)

Backend + Redis (or in-memory fallback) + client opt-in via settings.

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.meta.leaderboard_settings | Settings toggle enables/disables opt-in submit | [ ] | `LeaderboardSettings` in settings UI |
| M6.meta.leaderboard_submit_on | Opt-in **on** → escape submits clear time | [ ] | No error toast; API receives entry |
| M6.meta.leaderboard_submit_off | Opt-in **off** → escape does not submit | [ ] | Privacy respected |
| M6.meta.leaderboard_api | `GET /api/v1/leaderboards` returns entries | [ ] | curl or browser |
| M6.web.leaderboards_page | Web `/leaderboards` matches API ordering | [ ] | Same names/times/scores |

### Website (WEB-6.1–6.4)

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.web.landing_desktop | Landing page layout at 1920×1080 | [ ] | Brand-first hero; nav links work |
| M6.web.landing_mobile | Landing readable at ~390px width | [ ] | No horizontal scroll; tap targets OK |
| M6.web.register | Account register with email/password | [ ] | `/account` or auth flow |
| M6.web.login | Login returns session; logout works | [ ] | M6.web.account roll-up |
| M6.web.patch_notes | Patch notes page loads from JSON | [ ] | `apps/web/src/content/patch-notes/` |
| M6.web.wiki_stubs | Wiki index + stub pages render | [ ] | `apps/web/src/content/wiki/` |
| M6.web.nav_integration | Hub links or README paths reach web routes | [ ] | No 404 on primary pages |

### Accessibility (A11Y-6.1)

Settings menu (Esc → Settings). Changes should apply without relaunch where noted.

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.a11y.ui_scale | UI scale slider enlarges HUD/menus | [ ] | 100% vs 125%+ visibly different |
| M6.a11y.reduce_shake | Reduce camera shake dampens hit/damage shake | [ ] | Compare on vs off in combat |
| M6.a11y.colorblind_fire | Fire damage color distinct from physical/poison | [ ] | `AccessibilitySettings.get_damage_color()` |
| M6.a11y.colorblind_ice | Ice/frost damage color distinct | [ ] | Relevant in frozen biome |
| M6.a11y.subtitle_scale | Subtitle scale adjusts dialogue text size | [ ] | Hub NPC dialogue spot-check |
| M6.a11y.settings_persist | A11y prefs persist after quit/relaunch | [ ] | Saved via local save |

### Audio (frozen + cathedral)

Generator-tone stubs acceptable for M6; judge crossfade and identity, not final OGG quality.

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.audio.frozen_ambience | Frozen explore ambience distinct from other biomes | [ ] | Enter frozen run from hub |
| M6.audio.frozen_boss | Boss music crossfades on frost warlord engage | [ ] | No abrupt cut/pop |
| M6.audio.cathedral_ambience | Cathedral explore ambience distinct (gothic tone) | [ ] | Enter cathedral run |
| M6.audio.cathedral_boss | Boss music crossfades on cathedral hollow engage | [ ] | Matches boss room entry |

### Performance (PERF-6.1)

Reference: [performance_m6.md](performance_m6.md). Target: 1080p ≥60 FPS in typical combat rooms on mid-range PC.

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.perf.combat_room | 1080p combat room holds ~60 FPS with 8+ enemies | [ ] | Use F3/debug overlay if available |
| M6.perf.enemy_pool | No visible hitch when enemies spawn/despawn rapidly | [ ] | `EnemyPool` recycling |
| M6.perf.frozen_stutter | No sustained stutter in frozen courtyard/arena | [ ] | M6.perf.smoke roll-up |
| M6.perf.cathedral_stutter | No sustained stutter in cathedral hall/stairs | [ ] | Vertical rooms stress test |

### Integration with prior phases

| ID | Item | Status | Notes |
|----|------|--------|-------|
| M6.integration.hub_five_biomes | Hub portals for all 5 EA biomes selectable | [ ] | Castle, crystal, swamp, frozen, cathedral |
| M6.integration.hub_services | NPCs, merchant, blacksmith work after M6 runs | [ ] | M4 regression |
| M6.integration.continue_all_biomes | Continue works mid-run in each biome (spot-check) | [ ] | At least frozen + cathedral + one M5 biome |
| M6.integration.results_economy | Results screen XP/gold match escape outcome | [ ] | M4 economy rules |
| M6.integration.offline_default | New run works with API stopped (offline procgen) | [ ] | Aligns with M3.offline |

### M5 carry-over resolved in M6

| ID | Item | Status |
|----|------|--------|
| M5.deferred.item_roster | Full ~80-item catalog | [x] |
| M5.deferred.affix_pool | Expanded affix tables for epic+ | [x] |
| M5.deferred.mythic_uniques | Per-item Mythic rules | partial — affix counts only |
| M5.deferred.final_art | Pixel-diorama art / OGG / status icons | [ ] M7 |

### M6 carry-over → M7 (deferred / optional)

| ID | Item | Target | Status | Notes |
|----|------|--------|--------|-------|
| M6.deferred.oauth | Google/Discord OAuth on account page | M7/post-EA | [ ] | Email/password only in M6 |
| M6.deferred.input_remap | Full input remapping UI | M7 `POLISH-7.1` | [ ] | |
| M6.deferred.mythic_uniques | Per-item mythic unique behavior | M7 | [ ] | Affix min counts only |
| M6.deferred.status_icons | Status HUD icon art (not colored squares) | M7 | [ ] | |
| M6.deferred.ogg_audio | Final OGG tracks for frozen/cathedral | M7 | [ ] | Generator tones OK for M6 |
| M6.deferred.room_art | Pixel-diorama room meshes | M7 | [ ] | Blockout + materials OK for M6 |
| M6.deferred.theme_blind | Blind theme identification (all 5 biomes) | M7 | [ ] | Extends M5.theme.blind |

---

## M7 — EA polish & ship

Gate: [07-EA-DEFINITION-OF-DONE.md](../plan/07-EA-DEFINITION-OF-DONE.md), [M7_IMPLEMENTATION_LOG.md](M7_IMPLEMENTATION_LOG.md).  
Printable mirror: [M7_MANUAL_PLAYTEST_CHECKLIST.md](M7_MANUAL_PLAYTEST_CHECKLIST.md).

### Closed playtest (`SHIP-7.1`)

| ID | Item | Status |
|----|------|--------|
| M7.ship.external_playtest | ≥20 external playtesters completed full loop | [ ] |
| M7.ship.crash_rate | Crash rate within defined threshold | [ ] |
| M7.ship.qualitative | Playtesters remember combat/bosses/exploration over “the algorithm” | [ ] |

### Performance

| ID | Item | Status |
|----|------|--------|
| M7.perf.1080p60 | Mid-range PC: 1080p ≥60 FPS in typical combat rooms | [ ] |
| M7.perf.softlock_smoke | No softlocks in 50 automated seed smoke tests (also in CI) | [ ] |
| M7.perf.crash_reports | Crash produces actionable log/report path (playtest spot-check) | [ ] |
| M7.offline.no_hang | API down / offline → new run + continue playable, no hang | [ ] |

### Controller polish (`POLISH-7.1`)

See **M1 carry-over → M7 (gamepad)** above.

### Multi-floor dungeons (`FLOOR-7.x`)

| ID | Item | Status |
|----|------|--------|
| M7.floor.ten_clear | Complete 10-floor run (Forgotten Castle primary) | [ ] |
| M7.floor.seed_parity | Same seed → same floor layouts on regenerate | [ ] |
| M7.floor.secrets_max | Never more than 2 secret rooms on one floor | [ ] |
| M7.floor.stair_collision | Cannot walk through stair geometry | [ ] |
| M7.floor.stair_lever_ascend | Boss defeated → lever → ascend to new floor | [ ] |
| M7.floor.stair_lever_descend | Shift+interact descends to prior floor | [ ] |
| M7.floor.spawn_facing | After ascend, spawn at stair top facing into floor | [ ] |
| M7.floor.no_mid_portal | No escape portal before floor 10 final boss | [ ] |
| M7.floor.final_lobby | Floor 10 lobby: potion + buff scroll | [ ] |
| M7.floor.final_boss_phases | Final boss phase 1–3 readable and clearable | [ ] |
| M7.floor.continue | Quit mid-run → continue restores floor + layout | [ ] |
| M7.floor.leaderboard | Leaderboard records floor depth on clear | [ ] |
| M7.floor.chunk_single_active | Ascend unloads prior floor — only current floor in scene tree | [ ] |
| M7.floor.chunk_seed_restore | Continue/ascend regenerates floor from seed (no floor blob in save) | [ ] |

### Umbral Endless (`ENDLESS-7.x`)

| ID | Item | Status |
|----|------|--------|
| M7.endless.portal | Hub Umbral Endless portal opens menu (New / Continue) | [ ] |
| M7.endless.past_ten | Ascend past floor 10; no mid-run escape portal | [ ] |
| M7.endless.difficulty | Floor 11+ enemies scale per 10-floor tier | [ ] |
| M7.endless.continue | Continue restores endless run at saved floor | [ ] |
| M7.endless.skip_prompt | New run prompts if skip consumables in inventory | [ ] |
| M7.endless.skip_consume | Skip item consumed; run starts at mapped floor | [ ] |

### Umbral Waves (`WAVES-7.x`)

| ID | Item | Status |
|----|------|--------|
| M7.waves.portal | Hub Umbral Waves portal opens menu | [ ] |
| M7.waves.chests | All 10 lobby chests must open before Ready | [ ] |
| M7.waves.ready | Ready collapses walls; wave 1 spawns | [ ] |
| M7.waves.milestone_boss | Wave 5 includes boss + mobs | [ ] |
| M7.waves.prep | Milestone prep rebuilds walls + countdown | [ ] |
| M7.waves.isolated_inv | Main equipment not used; waves inventory only | [ ] |
| M7.waves.continue | Mid-run quit restores wave + waves inventory | [ ] |
| M7.waves.reward | 50-wave clear: pick 3 items to main inventory | [ ] |
| M7.waves.no_early_transfer | Fail/exit before wave 50: no item transfer | [ ] |
| M7.waves.equip_feel | Use/equip items from waves inventory during run (partial UI OK) | [ ] |

### Steam (`STEAM-7.x`)

| ID | Item | Status |
|----|------|--------|
| M7.steam.launch | Game launches via Steam (when SDK present) | [ ] |
| M7.steam.overlay | Shift+Tab overlay works | [ ] |
| M7.steam.achievement | Unlock appears in Steam client | [ ] |
| M7.steam.cloud | Save survives reinstall via chosen cloud path | [ ] |
| M7.steam.auth_deferred | Email auth still works without Steam ticket | [ ] |

### Tutorial (`POLISH-7.2`)

| ID | Item | Status |
|----|------|--------|
| M7.polish.hub_tips | First-run hub tips show | [ ] |
| M7.polish.hub_tips_skip | Esc skips all tips | [ ] |
| M7.polish.arena_roll | New player can learn roll in arena | [ ] |

### Release ship (`SHIP-7.x`)

| ID | Item | Status |
|----|------|--------|
| M7.ship.store_assets | Capsule, screenshots, trailer checklist | [ ] |
| M7.ship.hotfix_doc | Hotfix process documented | [ ] |
| M7.ship.ea_branch | Public Steam branch live | [ ] |
| M7.ship.known_issues | Known-issues list published (align with store page) | [ ] |

---

## Sign-off (current phase)

| Area | Pass | Notes |
| ---- | ---- | ----- |
| M1 KB/M combat arena | [x] | 2026-07-29 |
| M2 castle vertical slice | [x] | 2026-07-30 |
| M3 server generation (automated) | [x] | 2026-07-30 |
| M4 gameplay loop (automated) | [x] | 2026-07-30 |
| M5 content pack A (automated) | [x] | 2026-07-30 — `m5_suite` |
| M3 manual spot-checks | [ ] | Seed, offline, procgen-cli |
| M4 TEST-4.1 soak (manual) | [ ] | 10-run log in `m4_soak_notes.md` |
| M5 manual playtest (feel) | [ ] | Biomes, weapons, bosses, audio |
| M6 manual playtest (feel) | [ ] | § M6 above — 100 checklist IDs (99 open + 1 automated done); mirror: `M6_MANUAL_PLAYTEST_CHECKLIST.md` |
| M7 feel & UX (pending) | [ ] | § M7 — 49 IDs + 19 carry-over = 68 total; mirror: `M7_MANUAL_PLAYTEST_CHECKLIST.md` |

---

## Maintenance rules

1. **Closing a phase:** Mark automated items done in validation suites; move remaining human gates into the appropriate section above.
2. **New manual item:** Add a row with stable `ID` (e.g. `M5.hub.npc_dialogue_feel`); reference from `checklist_ref` in validation tests if partially automatable.
3. **Deleting phase playtest files:** When a phase closes, delete its dedicated playtest checklist (if any) and ensure all open items live here or in the phase implementation log’s deferred table.
