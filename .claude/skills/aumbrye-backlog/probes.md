# Runtime probes

For a question none of the diagnostics in `apps/game/client/scenes/debug/` answers, write a temporary
probe. A probe runs headless and does not write saves unless it starts a run or calls `LocalSave`.

## How to run one

1. Put the script in `apps/game/client/.godot/claude_probe/`. `.godot/` is git-ignored and still inside `res://`, so autoloads work. `--script` mode does not load autoloads, so it fails on `EnemyCatalog` and the rest.
2. Give it a matching scene:

```bash
D=apps/game/client/.godot/claude_probe; mkdir -p $D
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://.godot/claude_probe/NAME.gd" id="1"]\n\n[node name="Probe" type="Node"]\nscript = ExtResource("1")\n' > $D/NAME.tscn
timeout 110 godot --headless --path apps/game/client res://.godot/claude_probe/NAME.tscn 2>&1 | grep -E "PROBE|SCRIPT ERROR"
```

3. Delete the script and scene when done, naming each file.

Things that trip probes:
- **Warnings are errors, in probes too.** An unused local, integer division or a `:=` from an untyped array element is a parse error, and a probe that fails to parse never exits. Read the log for `SCRIPT ERROR` before raising the timeout.
- **Runtime errors inside a coroutine** mean `get_tree().quit()` never runs; always wrap runs in `timeout`.
- **`LocalProcgen.generate()` returns a wrapper.** The floor is `result.definition`, and `definition.placements.boss` can be null.
- **After adding a `class_name` script,** run `godot --headless --import --path apps/game/client` first.
- **A probe worth keeping** becomes `apps/game/client/scripts/tools/<name>_audit.gd` plus `scenes/debug/<name>_audit.tscn`, printing `<NAME> RESULT n failures` and calling `get_tree().quit(0 if ok else 1)` like the existing audits.

## Example: floor statistics

Generates floors for a few biomes and prints how many rooms, enemies, locks and rest rooms they hold
and how many occupied rooms hold more than one enemy.

```gdscript
extends Node


func _ready() -> void:
	var floors := 0
	var rooms := 0
	var enemies := 0
	var multi := 0
	var occupied := 0
	var with_lock := 0
	var with_rest := 0
	for biome in ["forgotten_castle", "poison_swamp", "iron_vault", "umbral_chapel", "prism_depths"]:
		for seed_index in 5:
			for floor_index in [1, 2, 3, 4]:
				var result: Dictionary = LocalProcgen.generate(
					biome, 500 + seed_index, floor_index, "castle", 1, 5, false, false, 0, {}
				)
				var definition: Dictionary = result.get("definition", {})
				if definition.is_empty():
					continue
				floors += 1
				rooms += (definition["rooms"] as Array).size()
				if not (definition["locks"] as Array).is_empty():
					with_lock += 1
				var per_room := {}
				for entry in definition["roomContent"]:
					if entry["contentType"] == "rest":
						with_rest += 1
						break
				for placement in definition["placements"]["enemies"]:
					per_room[placement["roomId"]] = int(per_room.get(placement["roomId"], 0)) + 1
					enemies += 1
				for count in per_room.values():
					occupied += 1
					if int(count) > 1:
						multi += 1
	print("PROBE floors %d rooms/floor %.1f enemies/floor %.1f multi %d/%d lock %d rest %d" % [
		floors, rooms / float(floors), enemies / float(floors), multi, occupied, with_lock, with_rest
	])
	get_tree().quit()
```

On 2026-10-01 it printed about 10.8 rooms and 9.3 enemies per floor, 61 % of occupied rooms holding
two or more enemies, and a lock and a rest room on every floor.
