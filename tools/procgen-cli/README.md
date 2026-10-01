# procgen-cli

Command-line wrapper around `packages/procedural`, the C# dungeon generator the backend uses. The
game does not call it: the Godot client generates floors with its own GDScript generator
(`apps/game/client/scripts/dungeon/local_procgen.gd`), and the two have diverged.

## Usage

```bash
dotnet run --project tools/procgen-cli -- generate forgotten_castle 42001
```

```
procgen-cli generate <biomeId> <seed> [runId] [--floor N] [--final-floor] [--tier N] [--player-level N]
procgen-cli mix-seed-table
procgen-cli room-kit-specs
```

`generate` prints canonical dungeon JSON on stdout. `mix-seed-table` and `room-kit-specs` print the
seed-mixing table and the room-kit specs the C# library uses.
