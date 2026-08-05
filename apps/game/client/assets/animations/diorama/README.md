# Diorama animation libraries

Authored `AnimationLibrary` resources compiled from `diorama_anim_library.gd` clip tables
against reference rigs (`player`, `melee`, `hound`).

## Regenerate

From `apps/game/client`:

```bash
godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd
```

Runtime controllers load these via `DioramaAnimLibrary.AUTHORED_LIBRARY_PATHS` and fall back
to per-rig compilation when a profile library is missing.
