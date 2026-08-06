extends RefCounted
class_name LocalProcgen

## Offline dungeon generation — GDScript two-phase procgen (primary), optional C# CLI for tooling.

const DEFAULT_BIOME := "forgotten_castle"
const CLI_RELATIVE := "tools/procgen-cli"
const PUBLISHED_EXE := CLI_RELATIVE + "/publish/procgen-cli.exe"
const DEBUG_EXE := CLI_RELATIVE + "/bin/Debug/net8.0/procgen-cli.exe"
const CSPROJ := CLI_RELATIVE + "/ProcgenCli.csproj"
const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")
const DungeonDefinitionValidatorScript := preload("res://scripts/dungeon/dungeon_definition_validator.gd")
const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const SEED_SALTS: Array[int] = [0, 0x9E3779B9, 0x85EBCA6B]


static func generate(
	biome_id: String = DEFAULT_BIOME,
	run_seed: Variant = null,
	floor_index: int = 1,
	run_mode: String = "castle",
	dungeon_tier: int = 1,
	player_level: int = 1,
	debug_ascii: bool = false,
	allow_cli_fallback: bool = false,
	bypass_tier_lock: bool = false
) -> Dictionary:
	var base_seed := _resolve_seed(run_seed)
	if run_seed == null:
		print("[LocalProcgen] Rolled seed: %d" % base_seed)
	if not bypass_tier_lock and not DungeonSeedService.can_access_tier(dungeon_tier):
		return {
			"ok": false,
			"error": "Tier %d is locked — clear the previous tier to use this seed." % dungeon_tier,
		}
	var tier_seed := DungeonSeedService.derive_tier_seed(base_seed, dungeon_tier)
	var floor_seed := DungeonSeedService.mix_floor_seed(tier_seed, floor_index)
	var is_final := RunFloorConfig.is_final_floor(floor_index, run_mode)

	var last_reason := ""
	for attempt in SEED_SALTS.size():
		var attempt_seed := floor_seed if attempt == 0 else floor_seed ^ SEED_SALTS[attempt]
		var gd_result := DungeonProcgenScript.generate(
			biome_id,
			attempt_seed,
			maxi(1, dungeon_tier),
			maxi(1, player_level),
			floor_index,
			is_final,
			debug_ascii
		)
		if not gd_result.get("ok", false):
			last_reason = RoomGraphGeneratorScript.last_validate_reason()
			if last_reason == "":
				last_reason = str(gd_result.get("error", "generation_failed"))
			continue
		var definition: Dictionary = gd_result.get("definition", {})
		var validation: Dictionary = DungeonDefinitionValidatorScript.validate(definition)
		for warning in validation.get("warnings", []):
			push_warning(
				"[LocalProcgen] seed %d warning: %s" % [base_seed, str(warning)]
			)
		if validation.get("ok", false):
			return {
				"ok": true,
				"definition": definition,
				"input_seed": base_seed,
				"tier_seed": tier_seed,
				"generation_seed": int(gd_result.get("generation_seed", attempt_seed)),
				"floor_index": floor_index,
				"run_id": str(gd_result.get("run_id", definition.get("runId", ""))),
				"generator": "gdscript",
				"warnings": validation.get("warnings", []),
				"attempts": attempt + 1,
			}
		var errors: Array = validation.get("errors", [])
		last_reason = str(errors[0]) if not errors.is_empty() else "validation_failed"

	if allow_cli_fallback:
		var cli_result := _generate_via_cli(
			biome_id, tier_seed, floor_index, is_final, dungeon_tier, player_level, floor_seed
		)
		if cli_result.get("ok", false):
			cli_result["input_seed"] = base_seed
			cli_result["tier_seed"] = tier_seed
			cli_result["generator"] = "cli"
		return cli_result

	return {
		"ok": false,
		"error": "procgen_failed",
		"reason": last_reason,
		"attempts": SEED_SALTS.size(),
		"input_seed": base_seed,
		"tier_seed": tier_seed,
		"generation_seed": floor_seed,
	}


static func _generate_via_cli(
	biome_id: String,
	tier_seed: int,
	floor_index: int,
	is_final: bool,
	dungeon_tier: int,
	player_level: int,
	floor_seed: int
) -> Dictionary:
	var invocation := _resolve_cli_invocation()
	if invocation.is_empty():
		return {
			"ok": false,
			"error":
			(
				"Local dungeon generator not found. Build with: "
				+ "dotnet build tools/procgen-cli/ProcgenCli.csproj"
			),
		}

	var run_id := DungeonProcgenScript.deterministic_run_id(floor_seed, biome_id, floor_index)
	var args: PackedStringArray = invocation.get("args", PackedStringArray())
	args.append("generate")
	args.append(biome_id)
	args.append(str(tier_seed))
	args.append(run_id)
	args.append("--floor")
	args.append(str(floor_index))
	if is_final:
		args.append("--final-floor")
	args.append("--tier")
	args.append(str(maxi(1, dungeon_tier)))
	args.append("--player-level")
	args.append(str(maxi(1, player_level)))

	var output: Array = []
	var exit_code := OS.execute(invocation.get("path", ""), args, output, true, false)

	if exit_code != 0:
		var err_text := _join_output(output).strip_edges()
		return {
			"ok": false,
			"error": err_text if err_text != "" else "procgen-cli exited with code %d" % exit_code,
		}

	var json_text := _extract_json_text(_join_output(output).strip_edges())
	if json_text.is_empty():
		return {"ok": false, "error": "procgen-cli returned empty output"}

	var parsed: Variant = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		return {"ok": false, "error": "procgen-cli returned invalid JSON"}

	var definition: Dictionary = parsed
	if definition.is_empty():
		return {"ok": false, "error": "procgen-cli returned empty dungeon definition"}

	var rooms: Array = definition.get("rooms", [])
	if rooms.is_empty():
		return {"ok": false, "error": "procgen-cli returned dungeon definition without rooms"}

	return {
		"ok": true,
		"definition": definition,
		"generation_seed": int(definition.get("seed", floor_seed)),
		"floor_index": floor_index,
		"run_id": str(definition.get("runId", run_id)),
	}


static func _resolve_seed(run_seed: Variant) -> int:
	if run_seed != null:
		return maxi(1, int(run_seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system() * 1000.0) ^ OS.get_process_id()
	return rng.randi_range(1, 2_147_483_646)


static func _repo_root() -> String:
	return ContentLoader.content_path("content").get_base_dir()


static func _resolve_cli_invocation() -> Dictionary:
	var root := _repo_root()
	var published := root.path_join(PUBLISHED_EXE)
	if FileAccess.file_exists(published):
		return {"path": published, "args": PackedStringArray()}

	var debug_exe := root.path_join(DEBUG_EXE)
	if FileAccess.file_exists(debug_exe):
		return {"path": debug_exe, "args": PackedStringArray()}

	var csproj := root.path_join(CSPROJ)
	if FileAccess.file_exists(csproj):
		return {
			"path": "dotnet",
			"args": PackedStringArray(["run", "--project", csproj, "--"]),
		}
	return {}


static func _join_output(lines: Array) -> String:
	var parts: PackedStringArray = []
	for line in lines:
		parts.append(str(line))
	return "\n".join(parts)


static func _extract_json_text(text: String) -> String:
	var start := text.find("{")
	if start < 0:
		return ""
	return text.substr(start)
