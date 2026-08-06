# Contributing to Aumbrye

Thank you for contributing. This repository uses a monorepo layout; read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for orientation.

## Branch model

- Default branch: `main`
- All changes land via pull request — no direct pushes to `main`
- Keep PRs focused; link related improvement docs when you are closing a named gap

## Validation before you open a PR

Run the full local suite:

```bash
node scripts/validate.mjs
```

Or run the four layers individually (same commands CI exercises):

```bash
dotnet test services/backend/Aumbrye.sln --configuration Release
```

```bash
npm run validate:strict
```

```bash
pip install ruff && ruff check tools/
```

```bash
godot --path apps/game/client --headless --script res://scripts/validation/validation_main.gd
```

Install [pre-commit](https://pre-commit.com/) and run hooks locally:

```bash
pre-commit install
pre-commit run --all-files
```

Hooks cover content JSON validation, Ruff on `tools/`, gdformat on health-critical GDScript files, and ESLint on staged `apps/web` sources.

## Documentation conventions

All documentation changes must follow [docs/DOC-CONVENTIONS.md](docs/DOC-CONVENTIONS.md):

- **Code is the only source of truth** — cite `path:line` or real identifiers; never document intent as implemented
- **Paired trees** — `docs/existing_codebase/<topic>.md` describes current behavior; `docs/actual_improvements/<topic>.md` describes gaps and target design. Topic filenames are mirrored between trees
- **Status tags** — use `IMPLEMENTED`, `PARTIAL`, `PLACEHOLDER`, `STUB`, `FAKE`, `BROKEN`, or `ABSENT` in status tables
- **No filler** — delete empty sections rather than writing placeholder prose

Relative Markdown links in `README.md` and `docs/` are checked in CI; broken links fail the build.

## License

By contributing, you agree that your contributions are licensed under the same terms as the repository. See [LICENSE](LICENSE).
