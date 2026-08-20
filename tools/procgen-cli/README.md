# procgen-cli

Local dungeon generator for offline Godot play. Uses the same `packages/procedural` library as the backend.

## Usage

```bash
dotnet run --project tools/procgen-cli -- generate forgotten_castle 42001
```

Output is canonical dungeon JSON on stdout.

## Ship with the game (optional)

```bash
dotnet publish tools/procgen-cli -c Release -o tools/procgen-cli/publish
```

Godot resolves `~~tools/procgen-cli/publish/procgen-cli.exe~~ (build output, produced by `dotnet publish`)` first, then `bin/Debug`, then `dotnet run`.
