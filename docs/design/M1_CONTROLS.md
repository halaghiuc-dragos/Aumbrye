# M1 combat controls (authoritative — permanently locked)

> **M1 closed 2026-07-29.** User signed off KB/M playtest.  
> **Do not rebind, remove, or replace these controls or movement behaviors** without explicit user request.  
> Rule 1 applies: extend only — never replace working bindings.  
> Locked decisions: [01-LOCKED-DECISIONS.md](../plan/01-LOCKED-DECISIONS.md) (`DEC-C01`–`DEC-C04`).  
> Referenced by: `M1_IMPLEMENTATION_LOG.md`, `combat_tuning_m1.md`, `CODING.md`, `systems/01-MOVEMENT-CAMERA.md`, `systems/02-COMBAT.md`.

---

## Keyboard and mouse

| Action | Binding | Notes |
|--------|---------|-------|
| Move | **WASD** | Camera-relative |
| Look | **Mouse** | Captured by default; Esc toggles capture |
| Sprint | **Left Shift** | Drains stamina while moving |
| Roll / dodge | **Space** | Camera-relative with WASD held; Space alone = short back step **opposite weapon/hitbox facing** |
| Jump | **F** | Coyote time + jump buffer |
| Light attack | **LMB** | 3-hit combo chain |
| Heavy attack | **RMB** | |
| Block + parry | **Q (tap)** | 0.18s parry window → 0.65s block → auto idle. **Not hold.** |
| Lock-on | **Middle mouse** | Toggle; break on death / out of range. **Camera unchanged.** **W/S** camera-relative as normal; **A/D** pure orbit strafe (~1.75m radius). |
| Reset duel | **R** | Arena only |
| Debug overlay | **F1** | i-frames, guard state, FPS, enemy HP |
| Hitbox draw | **F2** | Red hitboxes, blue hurtboxes |
| Damage numbers | **F3** | Toggle floating damage; **PARRIED** / **BLOCKED** on guard |
| Pause / mouse | **Esc** | Release or recapture mouse |

### Fluid gameplay (same bindings)

- Move while attacking.
- Move while in block phase (after parry window).
- Attacks do **not** cancel walk; walk does **not** cancel attacks.
- Tap **Q** only — no hold-to-block.

### Lock-on movement (locked behavior)

- **Camera and mouse look:** identical whether locked or not.
- **W / S:** camera-relative forward/back (unchanged).
- **A / D (while locked):** tangent orbit around target at ~**1.75m** horizontal radius — no radial pull toward enemy.
- **Unlock:** middle mouse restores normal A/D strafe.

---

## Gamepad (Xbox layout)

> Bindings are implemented in `project.godot`. **Manual playtest deferred** — no controller verified at M1 close. See [M1_IMPLEMENTATION_LOG.md](M1_IMPLEMENTATION_LOG.md).

| Action | Binding |
|--------|---------|
| Move | Left stick |
| Look | Right stick |
| Sprint | L3 (left stick click) |
| Jump | A |
| Dodge / roll | B |
| Light attack | RT |
| Heavy attack | Y |
| Block + parry | LT (tap) |
| Lock-on | RB |
| Zoom | D-pad ↑ / ↓ |
| Reset duel | R3 (right stick click) |
| Pause | Back / View |

Gamepad block uses the same **tap** guard sequence as keyboard **Q**. Lock-on orbit rules match KB/M (W/S = move stick forward/back relative to camera; A/D equivalent = left/right stick X while locked → orbit).

---

## Guard sequence (implementation)

Defined in `apps/game/client/scripts/combat/guard.gd`:

1. **IDLE** — tap `block` action (Q / LT).
2. **PARRY_WINDOW** (0.18s) — enemy attack contact → parry stagger (1.2s on grunt).
3. **BLOCKING** (0.65s) — frontal damage reduced; stamina drain per hit.
4. **IDLE** — auto end; no hold required.

Constants: `PARRY_WINDOW`, `BLOCK_DURATION`, `BLOCK_DAMAGE_REDUCTION`, `BLOCK_STAMINA_DRAIN_PER_HIT`.

---

## Removed / not used

| Old plan default | Current |
|------------------|---------|
| Hold Q to block | Tap Q committed sequence |
| E = parry | Merged into Q |
| Shift = dodge (if ever documented) | **Space** = dodge |
| Space = jump (if ever documented) | **F** = jump |
| Lock-on changes camera | Camera unchanged; orbit strafe only |
