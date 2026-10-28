# System Architecture — FMCW Radar Signal Processing Pipeline

This document describes how the seven processing stages fit together and how the codebase is
organized, so each stage can be tested and reviewed independently without duplicating logic or
parameters.

## 1. Pipeline overview

The project implements one physical processing chain, built up incrementally:

```
chirp synthesis --> target echo + delay/attenuation --> dechirp (mix) --> beat signal
      |
      v
range FFT (fast-time) --> range profile / range-FFT cube
      |
      v
Doppler FFT (slow-time, across chirps) --> Range-Doppler (RD) map
      |
      v
CA-CFAR (1D on range profile, 2D on RD map) --> detections (range, Doppler bin)
      |
      v
per-detection array processing (steering vectors, MUSIC / DBF) --> angle estimate
      |
      v
multi-target integration --> (range, velocity, angle) per detection vs. ground truth
      |
      v
real-dataset adapter --> same range/Doppler/CFAR functions --> real-data validation
```

Phases 1-6 build this chain stage by stage against synthetic data with known ground truth.
Phase 7 (and the optional Phase 7b) reuse the *same* processing functions against a real public
dataset, swapping only the data source.

## 2. Phase dependency graph

```
Phase 1 (signal model, single stationary target, single chirp)
   |  locks: chirp generation, dechirp/mixing convention, beat-frequency formula,
   |         complex-baseband decision, target-delay model
   v
Phase 2 (range FFT -> range axis, AWGN, multiple ranges)
   |  reuses: Phase 1 chirp + echo + dechirp functions
   |  adds:   frequency->range mapping, noise model, range-resolution check
   v
Phase 3 (chirp train, Doppler FFT, RD map)
   |  reuses: Phase 2 range-FFT stage, called once per chirp
   |  adds:   slow-time phase progression, T_CRI, Doppler axis, RD map
   v
Phase 4 (CA-CFAR, 1D and 2D)
   |  reuses: Phase 2 range profile (1D case) and Phase 3 RD map (2D case)
   |  adds:   guard/training windows, threshold scaling, edge handling
   v
Phase 5 (array + angle estimation)
   |  reuses: Phase 1-3 per-chirp signal generation, extended across Nrx elements
   |  adds:   steering vector model, spatial covariance estimation, MUSIC / DBF
   v
Phase 6 (full multi-target integration )
   |  reuses: everything above, unmodified, on a multi-target scenario
   |  adds:   detection-to-truth association, error quantification, summary plot/table
   v
Phase 7 / 7b (real-dataset validation)
      reuses: range FFT, Doppler FFT, CA-CFAR functions verbatim
      adds:   dataset-specific I/O and parameter mapping from real hardware metadata,
              plus an optional MTI/clutter-suppression stage (7b)
```

The dependency graph is linear and additive: a later stage doesn't require editing an earlier
stage's already-verified function.

## 3. Mathematical relationships preserved across phases

These quantities are established once (Phase 1/2) and stay the single source of truth for every
later phase — no phase redefines them locally with a different value or a different (even if
numerically similar) formula:

- Chirp slope: `S = B / Tchirp_active` [Hz/s]
- Beat frequency: `f_beat = 2*R*S/c` (equivalently `2*R*B/(c*Tchirp_active)`)
- Range mapping: `R = f_beat*c / (2*S)`
- Range resolution: `dR = c / (2*B)`
- Wavelength: `lambda = c / fc`
- Doppler frequency (two-way): `f_d = 2*v/lambda`
- Max unambiguous velocity: `v_max = lambda / (4*T_CRI)`
- Doppler resolution: `dv = lambda / (2*Nchirps*T_CRI)`
- Max unambiguous range (Nyquist on beat frequency): `R_max = Fs*c / (4*S)`
- Array phase term (per element n, spacing d, angle theta, evaluated at fc, not at f_beat):
  `phi_n = 2*pi*d*n*sin(theta)/lambda`

`Tchirp_active` (the linear-ramp duration used in the slope/beat-frequency formulas) and
`T_CRI` (chirp *repetition* interval — active ramp + idle/retrace time — used in the Doppler
formulas) are kept as two distinct named parameters, since collapsing them into one "Tchirp" is
a common, easy-to-miss error (`docs/engineering_decisions.md`, D2).

## 4. Software architecture

```
fmcw-radar-signal-processing/
├── README.md
├── config/
│   ├── get_radar_params.m           single source of truth for synthetic-scenario parameters
│   └── get_radical_dataset_params.m real RaDICaL hardware/timing parameters (Phase 7/7b)
├── src/                             phase demonstration scripts (thin orchestration only)
│   ├── phase1_signal_model.m
│   ├── phase2_range_processing.m
│   ├── phase3_range_doppler.m
│   ├── phase4_cfar_detection.m
│   ├── phase5_angle_estimation.m
│   ├── phase6_full_pipeline.m
│   ├── phase7_dataset_validation.m
│   └── phase7b_dataset_validation_mti_cfar.m   (optional MTI/clutter-suppression extension)
├── functions/                       reusable, independently testable building blocks
│   ├── signal/
│   │   ├── generate_chirp.m
│   │   ├── simulate_target_echo.m
│   │   ├── simulate_moving_target_echo.m
│   │   └── dechirp_mix.m
│   ├── processing/
│   │   ├── range_fft.m
│   │   └── doppler_fft.m
│   ├── detection/
│   │   ├── ca_cfar_1d.m
│   │   ├── ca_cfar_2d.m
│   │   ├── cluster_detections.m
│   │   └── associate_detections.m
│   ├── angle/
│   │   ├── steering_vector.m
│   │   ├── build_array_covariance.m
│   │   ├── estimate_covariance.m
│   │   ├── beamform_conventional.m
│   │   └── music_spectrum.m
│   ├── utils/
│   │   ├── validate_params.m        cross-phase invariant/Nyquist/consistency checks
│   │   ├── add_awgn.m
│   │   └── apply_window.m
│   └── plotting/
│       ├── plot_beat_fft.m
│       ├── plot_range_profile.m
│       ├── plot_range_doppler_map.m
│       ├── plot_cfar_results.m
│       ├── plot_angle_spectrum.m
│       ├── plot_full_scenario.m
│       └── plot_dataset_validation.m
├── tests/                           automated per-phase verification (assert-based)
│   ├── test_phase1_beat_frequency.m
│   ├── test_phase2_range_accuracy.m
│   ├── test_phase3_doppler.m
│   ├── test_phase4_cfar.m
│   ├── test_phase5_angle.m
│   ├── test_phase6_integration.m
│   └── test_phase7_dataset.m
├── results/                         generated figures
├── docs/
│   ├── architecture.md              (this file)
│   ├── engineering_decisions.md
│   ├── parameter_reference.md
│   ├── verification_strategy.md
│   ├── methodology.md
│   ├── dataset_notes.md             (Phase 7 dataset source, licence, hardware parameters)
│   └── dataset_comparison.md        (dataset selection rationale)
└── data/                            local-only dataset storage (git-ignored)
```

`config/` and `tests/` are organizational additions on top of the minimum needed —
folder layout only, doesn't change methodology, algorithms, or deliverables
(`docs/engineering_decisions.md`, D13).

### Layer responsibilities

- **`config/`** — the *only* place default numeric parameters are defined. Every phase script
  starts by loading a params struct and then overrides only the fields relevant to the
  demonstration it's running (e.g. a target list). It never redefines `fc`, `B`,
  `Tchirp_active`, `Fs`, etc. locally — no duplicated magic numbers.
- **`functions/`** — pure, unit-testable building blocks with explicit inputs/outputs and no
  hidden global state. Each function documents its assumptions (narrowband, stop-and-hop,
  square-law detection, etc.) in its header comment.
- **`src/`** — thin orchestration: load params, call functions in sequence, call plotting
  functions, save a figure to `results/`, and print/save the numeric verification for that
  phase. Phase scripts contain no independent re-derivation of formulas.
- **`tests/`** — machine-checkable pass/fail assertions with thresholds derived from FFT bin
  width or algorithmic resolution (see `docs/verification_strategy.md`).
- **`docs/`** — narrative documentation: architecture (this file), the engineering decision
  log, parameter reference, verification strategy, methodology write-up, and dataset notes.

## 5. Data shapes through the pipeline

Making tensor shapes explicit avoids silent orientation bugs later (e.g. transposing fast-time
and slow-time axes):

- Single chirp, single element: beat signal `s[n]`, `n = 1..Ns` (fast-time samples).
- Chirp train, single element (Phase 3): matrix `S[n, m]`, `n` = fast-time (1..Ns), `m` =
  slow-time / chirp index (1..Nchirps). Range FFT operates down columns (per chirp, over `n`);
  Doppler FFT operates across rows (per range bin, over `m`).
- Chirp train, array (Phase 5-7): cube `S[n, m, k]`, `k` = 1..Nrx (element index). Range/Doppler
  FFT operate identically per element; array processing operates along `k` at a fixed
  `(n, m)` range-Doppler cell.

This `[fast-time, slow-time, element]` axis order is fixed from Phase 3 onward and used
consistently by every function that touches the cube.

## 6. Toolbox boundary

- **Base MATLAB only** (`fft`, `ifft`, `fftshift`, `eig`, `meshgrid`) is sufficient for chirp
  generation, range/Doppler FFTs, CA-CFAR, steering vectors, and MUSIC's eigendecomposition.
  CFAR and MUSIC are implemented from scratch rather than depending on Phased Array System
  Toolbox (`docs/engineering_decisions.md`, D9), so the repository runs for a reviewer who only
  has Signal Processing Toolbox, or no toolboxes at all for most phases.
- **Signal Processing Toolbox** — used where it improves clarity without hiding the core
  algorithm: window functions (`hamming`) for sidelobe control in range/Doppler/angle spectra.
  `apply_window.m` falls back to a manual formula if this isn't available.
- **Phased Array System Toolbox** — optional, for cross-validation only (e.g. comparing the
  hand-built MUSIC spectrum against `phased.MUSICEstimator`), never the primary implementation.
- **Phase 7/7b dataset I/O** — `h5info`/`h5read`, both part of base MATLAB. No additional
  toolbox required.

## 7. Real-dataset validation (Phase 7 / 7b)

Phase 7 doesn't modify `functions/processing/*` or `functions/detection/*` at all — it reads the
RaDICaL dataset's raw complex ADC samples directly in `src/phase7_dataset_validation.m`, using
`config/get_radical_dataset_params.m` for the real radar's own hardware timing (a separate
parameter struct from the synthetic scenario's, since Phase 7 validates against a different,
real radar with its own fixed timing), and reuses `range_fft.m` / `doppler_fft.m` /
`ca_cfar_2d.m` / `cluster_detections.m` completely unmodified. Phase 7b adds an optional MTI
clutter-cancellation stage on top of the same real data, without touching Phase 7 or any shared
function — both remain independently runnable so the raw and clutter-suppressed results can be
compared side by side.
