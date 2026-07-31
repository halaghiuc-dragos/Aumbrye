extends RefCounted
class_name LocalProcgen

## Offline dungeon generation via procgen-cli (same C# library as server).

const DEFAULT_BIOME := "forgotten_castle"
const CLI_RELATIVE := "tools/procgen-cli"
const PUBLISHED_EXE := CLI_RELATIVE + "/publish/procgen-cli.exe"
const DEBUG_EXE := CLI_RELATIVE + "/bin/Debug/net8.0/procgen-cli.exe"
const CSPROJ := CLI_RELATIVE + "/ProcgenCli.csproj"


static func generate(
	biome_id: String = DEFAULT_BIOME,
	run_seed: Variant = null,
	floor_index: int = 1,
	run_mode: String = "castle"
) -> Dictionary:
	var base_seed := _resolve_seed(run_seed)
	var floor_seed := RunFloorConfig.mix_seed(base_seed, floor_index)
	var is_final := RunFloorConfig.is_final_floor(floor_index, run_mode)
	var invocation := _resolve_cli_invocation()
	if invocation.is_empty():
		return {
			"ok": false,
			"error": (
				"Local dungeon generator not found. Build with: "
				+ "dotnet build tools/procgen-cli/ProcgenCli.csproj"
			),
		}

	var args: PackedStringArray = invocation.get("args", PackedStringArray())
	args.append("generate")
	args.append(biome_id)
	args.append(str(floor_seed))
	if is_final:
		args.append("--final-floor")
	else:
		args.append("--floor")
		args.append(str(floor_index))

	var output: Array = []
	var exit_code := OS.execute(
		invocation.get("path", ""),
		args,
		output,
		true,
		false
	)

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
		"input_seed": base_seed,
		"generation_seed": int(definition.get("seed", floor_seed)),
		"floor_index": floor_index,
		"run_id": str(definition.get("runId", "")),
	}


static func _resolve_seed(run_seed: Variant) -> int:
	if run_seed != null:
		return maxi(1, int(run_seed))
	return randi_range(1, 2_147_483_646)


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
