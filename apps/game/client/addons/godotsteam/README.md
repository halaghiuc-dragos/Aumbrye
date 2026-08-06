# GodotSteam (optional)

Place GodotSteam 4.7 binaries for your platform under `win64/` and `linux64/` per
`godotsteam.gdextension`. Copy `steam_api64.dll` (Windows) or `libsteam_api.so`
(Linux) next to the exported game binary; the export preset `include_filter` lists
those files.

When binaries are absent the game runs in `SteamService` stub mode.
