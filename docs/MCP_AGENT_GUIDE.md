# MCP Agent Guide — Godot Tooling for Aumbrye

How an AI agent should use the two Godot MCP servers to implement `docs/design/AUDIT_2026-08.md` with maximum success and minimum wasted tokens.

**Validated 2026-08-03.** Both servers respond. Live editor is **Godot 4.7.1-stable, Windows, debug build, editor_scale 1.5**.

---

## 0. The two servers

| Server | Purpose | Status |
|--------|---------|--------|
| `project-0-Aumbrye-godot-mcp` | Live control of the running Godot editor: scenes, nodes, resources, shaders, animation, physics, audio, UI, debug, filesystem | ~75 tools |
| `project-0-Aumbrye-godot-mcp-docs` | Godot 4.7 official documentation: `get_documentation_tree`, `get_documentation_file` | 2 tools |

> **Duplicate servers exist.** `user-godot-mcp` and `user-godot-mcp-docs` expose identical tool names. **Always use the `project-0-Aumbrye-` prefixed pair.** The user-scoped ones may point at a different project root and will silently operate on the wrong scene tree.

---

## 1. The five rules that matter most

### Rule 1 — MCP is the live editor; native tools are the disk

This is the single biggest source of agent failure. They are two different states.

| You want to… | Use | Never use |
|---|---|---|
| Read or write **GDScript source** | `Read`, `StrReplace`, `Write` | `script_edit`, `script_manage` |
| Read or write **JSON content**, docs, configs | `Read`, `StrReplace`, `Write` | `filesystem_file`, `filesystem_json` |
| Search the codebase | `Grep`, `Glob` | `filesystem_search` |
| Inspect a **live scene tree** | `scene_hierarchy`, `node_query` | reading `.tscn` by hand |
| Inspect **runtime values** while playing | `debug_log`, `debug_performance` | anything on disk |
| Create/modify **nodes, materials, shaders, lights, animations** in a scene | MCP node/material/shader/lighting/animation tools | hand-editing `.tscn` text |
| Verify an edit actually loaded | `editor_filesystem`, `editor_status` | assuming |

**Why:** `script_edit` rewrites files from the editor's buffer. If you edited the same file with `StrReplace` in the same turn, one of the two writes is lost, and the resulting diff is unreviewable. Source code is a git artifact — keep it on disk, with normal tools, producing normal diffs.

**The rule in one line:** *text is disk, structure is MCP.*

### Rule 2 — Always fetch the schema before the call

`CallMcpTool` fails on guessed parameters, and every tool here is a multi-action dispatcher (`{"action": "get_info", ...}`). One `GetMcpTools` scoped to a server or tool, then call.

```
GetMcpTools { server: "project-0-Aumbrye-godot-mcp", toolName: "lighting_light" }
CallMcpTool { server: "...", toolName: "lighting_light", arguments: { action: "...", ... } }
```

Never call `GetMcpTools` with no arguments — it dumps the whole catalogue. Scope by `server`, or by `pattern` when you know the concept but not the tool (`pattern: "shader|material"`).

### Rule 3 — The editor must be open, and it is shared state

Every mutation lands in the user's actual editor. Treat it like someone else's desk.

- Confirm liveness with `editor_status { action: "get_info" }` before a batch of mutations.
- `editor_undo_redo` exists — know how to undo before you do something structural.
- Save deliberately via `scene_management`; do not leave the user with 30 unsaved scene changes.
- After you change files on disk, call `editor_filesystem` (rescan) so the editor picks them up. Otherwise `scene_run` executes stale code and you will debug a ghost.

### Rule 4 — Prefer narrow queries; full dumps are expensive

`scene_hierarchy { action: "get_tree" }` on `hub.tscn` returns roughly 25 KB of JSON in one call. `get_documentation_tree` returns 73 KB / 1678 lines.

- Call each **at most once per session** and remember the result.
- For a specific node, use `node_query` with a path such as `Player/WeaponController`, not a full tree dump.
- For docs, skip the tree entirely — the path format is predictable (see §3).

### Rule 5 — Close the loop: edit → rescan → run → read logs

The reason to have these servers at all is that you can *verify* instead of guess. Most audit items are falsifiable in under a minute. Use it.

```
1. StrReplace          fix the code on disk
2. editor_filesystem   { action: "rescan" }        editor sees the change
3. scene_run           { action: "play_custom", ... }  or play_main
4. debug_log           read output / errors
5. scene_run           { action: "stop" }
```

---

## 2. Tool families → what they are for

Grouped by the audit work they unblock. Names are exact.

### Inspection & discovery
| Tool | Use it for |
|---|---|
| `editor_status` | Liveness check, Godot version, current main screen |
| `project_info` | Project settings, enabled features |
| `project_settings` | Read/write settings — rendering, physics, window |
| `project_autoload` | **Audit §9.2** — enumerate and prune the 18 autoloads |
| `project_input` | **Audit §6** — the input map; needed for the estus key, aim mode, remapping UI |
| `debug_class_db` | Authoritative check that a class/method exists in **this** engine build |
| `scene_management` | Open, save, create, switch scenes |
| `scene_hierarchy` | Whole-tree dump (use sparingly) |
| `node_query` | Single node by path — properties, type, script |
| `editor_inspector` | What the user currently has selected |

### Scene & node construction
`node_lifecycle` (create/delete/duplicate) · `node_transform` · `node_property` · `node_hierarchy` (reparent) · `node_signal` · `node_group` · `node_metadata` · `node_call` · `node_visibility` · `node_physics` · `node_process`

Use these to build the scenes the audit asks for that do not exist yet: `title_screen.tscn`, `character_create.tscn`, `fp_viewmodel.tscn`, `diorama_character_rig_player.tscn`, rest-site and lore room prefabs.

### Art & rendering — the whole of Audit §7
| Tool | Audit item |
|---|---|
| `shader_shader`, `shader_shader_material` | Hit-flash uniform on `pixel_diorama_surface`, dissolve threshold, vignette pulse |
| `material_material`, `material_mesh` | Regenerating `mat_*.tres`, emissive conversion |
| `lighting_light` | Per-room-role lighting presets; **shadow probe promotion (§7)** |
| `lighting_environment` | Glow/bloom in the beauty preset, tonemap, SSAO |
| `lighting_sky` | `pixel_sky.gdshader` tuning |
| `particle_particles`, `particle_particle_material` | CPU→`GPUParticles3D` migration, effect pooling |
| `geometry_csg`, `geometry_gridmap`, `geometry_multimesh` | Verticality, pillars/cover, prop instancing at scale |

`lighting_light` plus `scene_run` is the exact loop for tuning `shadow_bias` / `shadow_normal_bias` live instead of recompiling — see §5.

### Animation — Audit §7.1 (P2 items)
`animation_player` · `animation_animation` · `animation_track` · `animation_tween` · `animation_animation_tree` · `animation_state_machine` · `animation_blend_space` · `animation_blend_tree`

Critical for the P2 gap: `anim_hitbox_on/off` are empty stubs. Use `animation_track` to add **method tracks** that call `enable_hitbox` / `disable_hitbox` on the real frames, then verify with `scene_run` + `debug_log`.

### Physics & navigation — Audit §3.3
`physics_physics_body` · `physics_collision_shape` · `physics_physics_query` · `navigation_navigation`

`physics_physics_query` is the fastest way to prove the doorway-seam collision gap. `navigation_navigation` is how you add the missing `NavigationLink3D` connections between rooms.

### Audio — the whole of Audit §8
`audio_bus` — create the `Master / Music / SFX / Ambience / UI` layout and write `default_bus_layout.tres`. Do this **with the tool**, not by hand-writing the resource file.
`audio_player` — place and test `AudioStreamPlayer3D` nodes.

### UI — Audit §7.1 (P4), §9 UI work
`ui_theme` — a real `Theme` resource is the correct answer to `GameUISkin`'s programmatic `StyleBoxFlat` sprawl.
`ui_control` — anchors, sizing, focus order (needed for gamepad navigation).

### Measurement
`debug_performance` — FPS, draw calls, memory. **This is how you build the missing perf gate** (Audit §9.1).
`debug_profiler` — find the actual hot spots before optimising.
`debug_log` — write markers into the Godot console from your own test drivers.

### Resources
`resource_query` · `resource_manage` · `resource_texture` — inspect `.tres`/`.res`, check dependencies, verify a texture imported with **nearest** filtering (matters for every pixel-art asset added under §7).

---

## 3. Using the documentation server

Two tools. The path format is `classes/class_<lowercase_classname>.md`.

```
get_documentation_file { file_path: "classes/class_gpuparticles3d.md" }
get_documentation_file { file_path: "classes/class_navigationlink3d.md" }
get_documentation_file { file_path: "classes/class_animationplayer.md" }
```

Non-class pages live under `tutorials/`, `about/`, `getting_started/`, `contributing/`.

**When to reach for it — do not skip these:**

1. **Before using any API you have not used in Godot 4.7 specifically.** Node names and signatures moved between 3.x and 4.x, and again within 4.x. Model priors are frequently 3.x.
2. **Shader work.** Built-ins differ per `shader_type` and per render mode. Check `tutorials/shaders/shader_reference/spatial_shader.md` before adding uniforms to `pixel_diorama_surface.gdshader`.
3. **Anything the audit names as a technology you must introduce:** `GPUParticles3D`, `Decal`, `NavigationLink3D`, `ImmediateMesh`, `RibbonTrailMesh`, `AudioEffectReverb`, `AudioEffectCompressor`, `FogVolume`, `OccluderInstance3D`, `AnimationNodeStateMachine`, `Theme`, `TranslationServer`.
4. **When `debug_class_db` says a member exists but you do not know its semantics.**

**Cost control:** call `get_documentation_tree` at most once, and only if a path guess has already failed. Prefer `debug_class_db` for a quick "does this method exist" — it answers from the live engine and is far cheaper than a full doc page.

---

## 4. Workflows for specific audit sections

### 4.1 Verifying the P0 procgen bug (Audit §1.1)

The claim is that every dungeon falls back to a fixed layout. Prove it before fixing it.

1. `debug_log` a marker in `room_graph_generator.gd` reporting `used_fallback` — or add a temporary print.
2. `editor_filesystem { action: "rescan" }`.
3. `scene_run { action: "play_main" }`, enter a dungeon twice with different seeds.
4. Read the output. If `used_fallback: true` both times, confirmed.
5. Fix, rescan, re-run, confirm two different layouts.

Do **not** ship the fix on reasoning alone. This one is cheap to falsify.

### 4.2 Promoting the shadow probe (Audit §7)

`scenes/debug/shadow_probe.gd` contains good tuned values behind a `PROBE_TUNE` env var: `SHADOW_ORTHOGONAL`, `max_distance 24.0`, `bias 0.01`, `normal_bias 0.2`.

1. `get_documentation_file { file_path: "classes/class_directionallight3d.md" }` — confirm property names for 4.7.
2. `lighting_light` to apply those values to the real scene light live.
3. `scene_run` and look at it.
4. Once it reads correctly, move the values into `visual_lighting.gd` / `pixel_diorama_settings.gd` with `StrReplace`.

### 4.3 Building the audio bus layout (Audit §8)

1. `get_documentation_file { file_path: "classes/class_audioserver.md" }`.
2. `audio_bus` to create `Music`, `SFX`, `Ambience`, `UI` under `Master`.
3. `audio_bus` to add `AudioEffectReverb` on `Ambience` and `AudioEffectCompressor` on `Music`.
4. Save the layout as `default_bus_layout.tres`, then reference it from `project_settings`.
5. Wire volume sliders in `settings_ui.gd` with `StrReplace` on disk.

### 4.4 Animation method tracks for hitboxes (Audit §7.1)

1. `get_documentation_file { file_path: "classes/class_animation.md" }` — method track API.
2. `animation_player` to locate the clip; `animation_track` to add the call track.
3. `scene_run`, attack, confirm via `debug_log` that hitbox enable fires on the intended frame.
4. Only then delete the JSON-timer path.

### 4.5 Establishing the perf gate (Audit §9.1)

`debug_performance` gives FPS, draw calls, and memory from the running game. Capture a baseline now, before any §7 VFX work, so the GPU-particle migration can be proved a win rather than assumed one.

---

## 5. Anti-patterns

| Do not | Because | Instead |
|---|---|---|
| Edit GDScript with `script_edit` | Fights `StrReplace`, produces unreviewable diffs, can lose writes | `Read` + `StrReplace` |
| Guess tool arguments | Every tool is an action dispatcher; the call just fails | `GetMcpTools` first |
| Call `get_documentation_tree` more than once | 73 KB per call | Guess `classes/class_<name>.md` |
| Dump `scene_hierarchy` repeatedly | ~25 KB per call | `node_query` on a path |
| Mutate the editor without checking it is live | Silent failures or wrong project | `editor_status` first |
| Run `scene_run` without a matching `stop` | Leaves a running instance holding file locks | Always stop |
| Assume disk edits are visible to the editor | Godot caches; you will test stale code | `editor_filesystem` rescan |
| Use `user-godot-mcp` | May target a different project root | Use `project-0-Aumbrye-` |
| Hand-write `.tres` / `.tscn` text | Format is version-sensitive and easy to corrupt | Resource/material/node tools |
| Trust an audit claim you have not reproduced | Several audit items are code-reading inferences | Reproduce with `scene_run` |

---

## 6. Session checklist

**Start**
1. `editor_status { action: "get_info" }` — confirm live, note the version.
2. `scene_management` — know which scene is open before you touch anything.
3. Read the relevant audit section; identify which claims are inferred and need reproduction.

**During**
4. `GetMcpTools` scoped, then `CallMcpTool`.
5. Source code and JSON on disk with native tools; scenes, resources, and runtime through MCP.
6. `editor_filesystem` rescan after every disk edit that the editor must see.
7. Verify with `scene_run` + `debug_log` rather than declaring success.

**End**
8. Stop any running scene.
9. Save or explicitly revert scene changes — never leave ambiguous unsaved state.
10. `ReadLints` on every file touched.
11. Report which audit items are now *verified* fixed versus *believed* fixed. The distinction matters.

---

## 7. Quick reference

```
# liveness
editor_status        { action: "get_info" }

# what am I looking at
scene_management     { action: "get_current" }
node_query           { action: "get_info", node_path: "Player/WeaponController" }

# does this API exist in 4.7
debug_class_db       { action: "...", class_name: "GPUParticles3D" }

# read the manual
get_documentation_file { file_path: "classes/class_gpuparticles3d.md" }

# make the editor see disk edits
editor_filesystem    { action: "rescan" }

# test
scene_run            { action: "play_main" }
debug_performance    { action: "get_info" }
scene_run            { action: "stop" }
```

Known live scene paths for orientation: `res://scenes/hub/hub.tscn` (root `AumbryeTower`), player at `Player` with children `Health`, `Stamina`, `Poise`, `Dodge`, `Guard`, `CombatReactions`, `StatusController`, `WeaponController`, `HitFeedback`, `LockOn`, `Hurtbox`, `Facing/WeaponPivot/Hitbox`, `CameraPivot/SpringArm3D/Camera3D`.
