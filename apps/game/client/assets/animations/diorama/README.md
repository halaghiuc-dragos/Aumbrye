# Diorama animation libraries

Authored `AnimationLibrary` resources compiled from `diorama_anim_library.gd` clip tables
against reference rigs (`player`, `melee`, `hound`, `shield`, `brute`, `ranged`).

## Regenerate

From `apps/game/client`:

```bash
godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd
```

Verify the committed outputs without writing:

```bash
godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd -- --verify
```

Export a single profile:

```bash
godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd -- --profile player
```

Rewrite only `digests.json`:

```bash
godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd -- --digests
```

## Files

| File | Role |
|------|------|
| `*_locomotion.res` | Six committed `AnimationLibrary` resources |
| `digests.json` | SHA-256 digests of the canonical library content for CI drift detection |

Rest poses are derived at export time via `DioramaCharacterSkin.rest_pose_for_profile`.
Method tracks target `../../AnimDirector` for `player` and `../../AnimController` for the
five enemy profiles. Each library also carries a reserved `__pose__` marker animation used
to reject stale authored resources at bind time.

Runtime controllers load these via `DioramaAnimLibrary.AUTHORED_LIBRARY_PATHS` and fall back
to per-rig compilation when the live rest pose does not match the baked fingerprint.
