# Verification Strategy

This document defines how correctness is judged for each phase, so a good-looking plot is never
treated as sufficient evidence on its own.

## 1. Three layers of verification, used together

1. **Theoretical vs. simulated numeric comparison** (printed by each phase script). For every phase,
   compute the theoretical prediction from the formulas in `docs/architecture.md`, measure the
   simulated/estimated result, and report absolute and relative error, plus the error *relative
   to the relevant resolution cell* (FFT bin width, Doppler bin width, or angular resolution) —
   never a bare "close enough."
2. **Automated assertions** (`tests/`), runnable independently of the demonstration scripts,
   with thresholds derived from a resolution quantity, never an arbitrary tolerance.
3. **Cross-method self-consistency checks**, independent of comparing against theory at all —
   these catch bugs that happen to still satisfy the theoretical formula by coincidence (e.g. a
   sign error that cancels out in one direction of motion but not the other).

## 2. Per-phase verification plan

### Phase 1 — beat frequency

- Theoretical: `f_beat = 2*R*S/c` for the configured test range.
- Measured: FFT peak bin of the simulated beat signal.
- Pass criterion: `abs(measured - theoretical) <= 1 * (Fs/Nfft_range)` (within one FFT bin).
- Test: `tests/test_phase1_beat_frequency.m`, `assert(error_hz <= bin_width_hz)`.

### Phase 2 — range accuracy and resolution

- Theoretical: `R = f_beat*c/(2*S)` per test target; `dR = c/(2*B)`.
- Measured: range-FFT peak location (converted to meters) for each of 2-3 test ranges.
- Pass criterion: peak within one range bin of injected range, for every test range (confirms
  the range axis scales correctly, not just that one point lines up).
- **Resolution stretch test:** place two targets separated by approximately one `dR`, confirm
  they're distinguishable as two peaks.
- Test: `tests/test_phase2_range_accuracy.m`.

### Phase 3 — Doppler / Range-Doppler map

- Theoretical: `v_max = lambda/(4*T_CRI)`, `dv = lambda/(2*Nchirps*T_CRI)`.
- Measured: RD-map peak (range bin, Doppler bin) for a stationary target (expect zero-Doppler
  bin), a positive-velocity target, and a negative-velocity target.
- Pass criterion: range within one range bin, velocity within one Doppler bin, correct sign of
  velocity recovered (a direct check that the complex-baseband decision, D3, works).
- **Cross-method check (D6):** compare the RD map generated via (a) explicit per-chirp analytic
  delay recomputation vs. (b) closed-form slow-time Doppler phasor applied to a single static
  beat signal. These must agree to near machine precision; a discrepancy indicates a
  stop-and-hop or phase-convention bug independent of whether either method matches theory.
- Test: `tests/test_phase3_doppler.m`.

### Phase 4 — CA-CFAR

- Theoretical: threshold factor `alpha = Ntrain*(Pfa^(-1/Ntrain) - 1)`; expected false-alarm
  rate on pure-noise cells ~ configured `Pfa`.
- Measured: (a) fraction of injected targets flagged as detections (should be 100% at the
  configured SNR); (b) empirical false-alarm rate measured on a noise-only region, compared
  against configured `Pfa` across a multi-decade sweep.
- Pass criterion: all injected targets detected; empirical Pfa within the same order of
  magnitude as configured Pfa (exact equality isn't expected — this is a Monte Carlo estimate
  over a finite number of noise cells).
- Explicitly documented: CA-CFAR's known failure modes near clutter edges (mismatched training
  statistics either side of an edge) and closely-spaced multiple targets (mutual masking, one
  target's energy inflating the other's training average).
- Test: `tests/test_phase4_cfar.m`.

### Phase 5 — angle estimation

- Theoretical: injected target angle(s).
- Measured: MUSIC (and DBF, for comparison) spectrum peak location.
- Pass criterion: peak within one angular resolution cell of the injected angle, for each of
  2-3 test angles.
- **Resolution differentiator test:** two targets closely spaced in angle (closer than the DBF/
  array beamwidth), confirming MUSIC resolves them as two peaks where conventional DBF shows one
  broadened peak.
- Test: `tests/test_phase5_angle.m`.

### Phase 6 — full multi-target integration 

- Theoretical: ground-truth (range, velocity, angle) per target in a 4-target scenario.
- Measured: estimated (range, velocity, angle) per detection, after CFAR detection and
  per-detection MUSIC angle estimation.
- Pass criterion: detection-to-truth association is unambiguous (targets separated by more than
  one resolution cell in at least one dimension), and mean/max error across targets is reported
  quantitatively for each of range, velocity, and angle.
- Test: `tests/test_phase6_integration.m`, asserting each target's error is within a small
  multiple (1-2x) of that dimension's resolution cell.

### Phase 7 / 7b — real-dataset validation

- No ground truth in the same sense as the synthetic phases — the RaDICaL sample used has no
  annotated target positions for this frame.
- Verification is qualitative-but-rigorous instead: every derived theoretical quantity (range
  resolution, max range, Doppler resolution, max velocity) is checked for internal consistency
  against the real radar's own hardware timing, and the resulting RD map and CFAR detections are
  checked for physical plausibility (energy at plausible ranges/velocities for an indoor
  recording, not saturating every cell or detecting nothing) rather than compared to an exact
  answer.
- Test: `tests/test_phase7_dataset.m`.

## 3. Regression protection

Each phase's test file is independently runnable and re-checks that phase's own assertions.
Before a phase is treated as complete, prior phases' tests are re-run to confirm nothing broke —
a later change (e.g. to `functions/processing/range_fft.m` while building Phase 5) must not
silently change an earlier phase's already-verified accuracy.

## 4. Reproducibility record

Every phase's report records the theoretical vs. measured comparison, the fixed RNG seed (42,
`docs/parameter_reference.md`), and the exact parameter values in effect (via
`get_radar_params()`/`get_radical_dataset_params()`, so a report is reconstructible from the
config alone).

## 5. Engineering-integrity rule

A phase isn't marked PASS unless the numeric verification in this document
actually ran and actually passed. A phase with an unresolved verification failure is reported as
FAIL or CONDITIONAL, with the specific discrepancy and suspected cause stated.
