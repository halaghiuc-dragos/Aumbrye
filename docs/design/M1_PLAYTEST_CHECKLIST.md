# M1 playtest checklist (signed off)

> **M1 closed 2026-07-29.** KB/M playtest passed. Controls locked in [M1_CONTROLS.md](M1_CONTROLS.md).  
> Gamepad section deferred → [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md) § M1 / M7.

## Setup

1. Open `apps/game/client` in Godot 4.7.
2. Run `combat_arena.tscn`.
3. Press **F1** — confirm FPS line shows (target: **≥ 60** on your PC).

## KB/M — core loop

| Step | Action | Pass? |
|------|--------|-------|
| 1 | WASD move, mouse look, sprint drains stamina | [x] |
| 2 | F jump, Space dodge; F1 shows i-frames during roll | [x] |
| 3 | LMB light combo, RMB heavy; stamina costs apply | [x] |
| 4 | Tap Q — parry window then block; F1 shows states | [x] |
| 5 | Middle-mouse lock-on; **W/S** normal, **A/D** orbit strafe; camera unchanged | [x] |
| 6 | F2 hitboxes visible; attacks hit dummy; Enemy HP drops | [x] |
| 7 | Kill dummy — collapse animation; **R** resets duel | [x] |

## Gamepad (Xbox layout) — deferred

_No controller at M1 close. Bindings exist in `project.godot`; verify when hardware available._

| Step | Action | Pass? |
|------|--------|-------|
| 1 | Full duel completable without mouse/keyboard | [ ] |
| 2 | Lock-on + target switch (right stick while locked) | [ ] |

## ENEMY-1.3 — win strategies

| Strategy | How | Pass? |
|----------|-----|-------|
| **Roll** | Dodge through active frames (0.15s); punish in recovery (0.9s) | [x] |
| **Parry** | Tap Q as attack lands in first 0.18s; enemy staggers 1.2s | [x] |
| **Spacing** | Back out during 0.7s windup; re-enter during recovery | [x] |

## Optional debug

- **F3** — damage numbers; **PARRIED** / **BLOCKED** (+ chip on block).
- **F1** — FPS, guard state, attack overlap count.
- **Parry HUD** — gold **PARRY** bar on Q tap.

## Playtest notes (2026-07-29)

- FPS **> 120** on playtest machine.
- Block/parry, lock-on orbit strafe, weapon-facing backstep dodge — all signed off.
- Controls and movement behaviors **permanently locked** per user request.

## Sign-off

- [x] User confirmed M1 KB/M complete (2026-07-29).
- [x] `combat_tuning_m1.md` updated.
- [x] `M1-COMBAT.md` removed; archive in `M1_IMPLEMENTATION_LOG.md`.
