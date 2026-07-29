# System: Performance

## Targets

| Platform | Resolution | Min | Aspire |
|----------|------------|-----|--------|
| Desktop | 1080p | 60 FPS | 144 FPS |
| Web | 1080p | 60 FPS | — (experimental) |

## Budgets

- ≤12 active AI agents in a combat room
- Load adjacent rooms only
- Atlased nearest textures
- Dual music buses crossfade ≤1s

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| PERF-6 | Content perf pass | M6 |
| PERF-7 | Optimization sprint | M7 |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| PERF-6.1 | Streaming/pooling/lights | M6 |
| PERF-7.1 | Profile + fix top costs | M7 |
| PERF-7.2 | Logging + crash hooks | M7 |

Document target hardware profile in `docs/design/perf_target_machine.md` during PERF-6.1.
