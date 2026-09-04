# Release checklist

`docs/MVP_DEPTH_PLAN.md` SY-11. Run this before any export leaves the building. Everything here is
manual by design — this repo has no CI and none is being added (`CLAUDE.md`).

## 1. Version bump — one step, five places

The client and backend gate on an exact version match (`X-Client-Version` header vs
`ApiVersions.ExpectedClientVersion`); moving one of the first four alone 426s every client of the
others. Bump all five together, in the same commit:

| # | File | Field |
|---|---|---|
| 1 | `apps/game/client/project.godot` | `config/version` |
| 2 | `apps/game/client/scripts/net/api_config.gd` | `CLIENT_VERSION` |
| 3 | `apps/web/package.json` | `version` (compiled into `__APP_VERSION__`) |
| 4 | `apps/web/package-lock.json` | both `version` fields (root + `packages[""]`) — or just re-run `npm install` in `apps/web/` to regenerate |
| 5 | `packages/shared/Contracts/ApiVersions.cs` | `ExpectedClientVersion` |

As of 2026-09-04 all five were reconciled to `0.6.0` — they had drifted to `0.4.0` while
`apps/web/content/patch-notes/0.6.0.md` (dated 2026-07-31) already described a shipped 0.6.0. Author
a new patch note for whatever this bump actually ships, rather than reusing 0.6.0.0's — that's
release content, not a mechanical step, and belongs to whoever is cutting the release.

`project_structure.json` also carries a stale `version` field, but it is a generated artifact
(`generatedBy: tools/generate_project_structure.py`) — regenerate it with that tool rather than
hand-editing; it is already stale on several other fields (script/scene counts) independent of
version and isn't part of the five-place gate above.

## 2. Steam app id

`SteamService._resolve_app_id()` used to `str()` the JSON number from `config/platform.json` before
checking `is_valid_int()` — `JSON.parse_string()` always returns a JSON number as a GDScript float,
so `480` became `"480.0"`, which is not a valid int string, so this branch never fired and every
build silently fell back to the dev app id. Fixed 2026-09-04 (check `raw_id is float or raw_id is
int` before falling back to string parsing). Confirm on export:

```
SteamService.is_stub_mode == false
```

An exported build that logs stub mode shipped with the dev app id — do not release it.

## 3. DebugConsole and DebugOverlay cannot open in release

Both already gate correctly — confirmed by reading the code, not by export testing (no export
environment available in this pass):

- `DebugConsole._input()` and `_ready()` both check `OS.is_debug_build()` before registering
  commands or handling the toggle input; `_commands` stays empty in a release build even if the
  toggle somehow fired.
- `DebugOverlay.show_debug` defaults to `OS.is_debug_build()`.

Re-verify with an actual exported build once one is available — this is a code-read confirmation,
not a substitute for launching the export and pressing the debug-console key.

## 4. Export + smoke pass (needs an export environment)

Not run in this pass — no export templates/environment available. When run:

1. Export each platform (Windows, Linux, macOS).
2. Copy `content/` next to the binary (`ContentLoader` resolves it at runtime; there is no CI step
   that does this — see `apps/game/client/scripts/app/content_loader.gd`).
3. Launch, and confirm:
   - No placeholder-SFX warning from `AudioDirector._report_placeholder_sfx()` (AU-01 — as of this
     pass eleven placeholder cues are still not replaced; this will still warn until AU-01 lands).
   - No `push_error` during boot.
   - `godot --headless -- --smoke-test`-equivalent pass over the exported binary, not only the
     editor project.
   - A save round-trips: create a character, make progress, quit, relaunch, confirm state.
   - `SteamService.is_stub_mode == false` on the Steam build (see §2).

## 5. Public site accuracy

Not verified in this pass — outside `apps/game/client/`, lower priority than the gameplay work this
plan otherwise tracks. Known as of the plan's authoring: `apps/web/src/content/biomes.json`,
`apps/web/content/wiki/biomes.md` and `apps/web/index.html`'s meta description described five biomes
when ten ship; `apps/web/content/wiki/controls.md` advertised a "Q parry" binding that does not exist
and omitted heavy attack, weapon arts, two-handing, healing and the quick slots. Check these against
`apps/game/client/project.godot`'s `[input]` section and `content/biomes/*.json` before shipping.

## 6. `apps/web/nginx.conf` cache headers

Not verified in this pass. Add `no-cache` for `index.html`, `immutable` for the hashed bundle, and
the four standard security headers, so a stale `index.html` cannot defeat `VersionGate`'s
cache-busting reload.
