# Audio

Each biome folder holds its ambience, explore and combat loops and boss theme; `shared/` holds the hub theme and the stingers; sound effects are `.ogg` files under
`sfx/`, wired through `content/audio/sfx.json` (the single cue table `AudioDirector` plays from).
Effects are mono and loudness-normalised; the weather loops stay stereo.

`node scripts/validate.mjs --layer content` fails when a cue in `sfx.json` names a file that does not
exist or two cues share one file; `res://scenes/debug/audio_voice_lifecycle_audit.tscn` checks that
pooled voices release their listeners.
