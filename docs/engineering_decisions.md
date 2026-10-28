# Engineering Decisions Log

This log records the non-obvious design decisions made while building this pipeline, and every
real bug found along the way — with root cause, fix, and how it was verified. The goal is to
make choices traceable rather than arbitrary, and to be honest about what actually went wrong
and how it was found and fixed.

Each numeric default in this log is also carried in `docs/parameter_reference.md`; this file
carries the *reasoning*, that file carries the *table*.

---

## D1 — Waveform: sawtooth linear FMCW, not triangular

**Decision:** Use a sawtooth (single up-chirp, then fly-back/idle, repeat) rather than a
triangular (up-down) chirp.

**Rationale:** Sawtooth avoids the up-chirp/down-chirp pairing logic needed to resolve the
range/velocity coupling that a triangular waveform introduces — unnecessary complexity for a
pipeline whose Doppler estimate already comes cleanly from the slow-time FFT across chirps.

**Alternatives considered:** Triangular chirp (adds range-Doppler coupling resolution logic,
better suited to hardware that can't do a fast fly-back, not needed here).

**Consequences:** Every up-chirp gives one clean, positive beat frequency per target. No
paired-chirp bookkeeping required in later stages.

---

## D2 — Two distinct timing parameters: `Tchirp_active` vs. `T_CRI`

**Decision:** Keep the active linear-ramp duration (`Tchirp_active`, used in the slope and
beat-frequency formulas) and the full chirp repetition interval (`T_CRI` = active ramp + idle
time, used in the Doppler formulas) as two separate named fields in the parameter struct, never
one shared `Tchirp`.

**Rationale:** The Doppler formulas depend on the chirp repetition interval, which differs from
the ramp duration used in the range/beat-frequency formulas the moment a chirp includes
idle/retrace time — true of any real hardware. Silently reusing the ramp duration in the Doppler
formula is a common, easy-to-miss error that produces a self-consistent-looking but wrong
`v_max`/`dv`. Naming the two fields differently makes the distinction hard to lose track of.

**Alternatives considered:** Single `Tchirp` with zero idle time. Rejected because it's
physically unrealistic (no real ADC/synthesizer has zero retrace/settle time) and would hide
this exact pitfall rather than demonstrate an understanding of it.

**Consequences:** `T_CRI > Tchirp_active` is enforced as an invariant in `validate_params.m`.

---

## D3 — Complex baseband (I/Q) representation, not real-valued IF sampling

**Decision:** Model the dechirped beat signal as complex-valued (in-phase/quadrature), as
produced by a quadrature dechirp mixer, rather than a real-valued IF signal.

**Rationale:** A real-valued signal's FFT is Hermitian-symmetric, so the sign of the Doppler
shift (approaching vs. receding target) is lost — only `|v|` is recoverable, not direction.
Complex baseband preserves the sign of the Doppler frequency through an `fftshift`-centered
complex FFT. This is standard in modern FMCW/mmWave receivers, and is needed for the
"positive velocity vs. negative velocity" verification to mean anything.

**Alternatives considered:** Real IF sampling with a separate direction-disambiguation scheme
(e.g. triangular waveform). Rejected as unnecessary complexity given D1.

**Consequences:** All beat-signal generation functions return complex data; `range_fft`/
`doppler_fft` operate on complex input; no `fftshift` is needed on the range axis (beat
frequencies are one-sided/positive by the mixing convention in D4), but `fftshift` *is* needed
on the Doppler axis to center zero-Doppler and show negative velocities.

---

## D4 — Dechirp mixing convention (sign of beat frequency)

**Decision:** Beat signal = transmitted chirp replica multiplied by the **conjugate** of the
received echo (`tx .* conj(rx)`), fixed for the whole project.

**Rationale:** For the up-chirp phase convention used in `generate_chirp.m`
(`phi(t) = pi*S*t^2`, instantaneous frequency increasing from 0 to B), this convention yields a
positive beat frequency for a positive target delay (`f_beat > 0` for `R > 0`), consistent with
`f_beat = 2*R*S/c` as used throughout. Fixing this convention once, in a single shared function,
prevents an accidental sign flip between stages.

**Consequences:** `functions/signal/dechirp_mix.m` is the only place this multiply happens; no
script re-implements dechirping locally.

**Correction (found during first testing):** This was originally coded with the opposite
mixing order, `rx .* conj(tx)`. Testing the beat signal's FFT showed the peak landing near DC
instead of the expected beat frequency. Working through the closed-form instantaneous frequency
of the mixed signal (via the phase derivative) by hand showed `rx .* conj(tx)` gives
`f_beat = -S*tau` — right magnitude, wrong sign — while `tx .* conj(rx)` gives
`f_beat = +S*tau`, matching theory exactly before any FFT bin quantization. Corrected in
`dechirp_mix.m` before any later stage was built on top of it, so no rework was needed beyond
this one function.

---

## D5 — Target delay modeled analytically, not by discrete sample-shifting

**Decision:** The received echo is generated by evaluating the transmit chirp's closed-form
instantaneous-phase expression at `(t - tau)`, where `tau = 2R/c`, rather than by shifting the
discrete transmit-signal array by a rounded number of samples.

**Rationale:** Since the chirp's phase is known analytically, this avoids interpolation error
and quantization of the delay to the sample grid, which would otherwise look like a real
processing error rather than what it actually is — a modeling shortcut. It also keeps the
Phase 1 beat-frequency check clean: any deviation from theory is attributable to FFT bin
quantization alone, not to delay-modeling error.

**Consequences:** Target range can be any real number, not constrained to the sample grid.

---

## D6 — Stop-and-hop approximation for moving targets (Phase 3+)

**Decision:** Within a single chirp, the target range is treated as constant (delay computed
once per chirp); range advances only chirp-to-chirp (`R(m) = R0 + v*m*T_CRI`) to produce the
slow-time Doppler phase progression.

**Rationale:** This is the standard "stop-and-hop" approximation used throughout automotive/
mmWave FMCW processing. Its validity condition is that the range change *during one chirp*
(`v * Tchirp_active`) is much smaller than the range resolution `dR = c/(2B)` — checked
numerically against the chosen parameters rather than assumed.

**Consequences:** There are two mathematically equivalent ways to generate the moving-target
signal — recomputing the analytic delay per chirp, or applying a closed-form slow-time Doppler
phasor `exp(j*4*pi*v*m*T_CRI/lambda)` to a single static beat signal — and cross-checking them
against each other is a cheap self-consistency test, independent of comparing either to theory.

---

## D7 — MUSIC spatial-covariance estimation strategy

**Decision:** For a given detected range bin, form one `Nrx x 1` spatial snapshot per chirp
(the array-channel vector at that range bin, taken *before* Doppler-domain separation), and
estimate the spatial covariance by averaging the outer product across all `Nchirps` snapshots
in the frame: `R_hat = (1/Nchirps) * sum_m x_m x_m^H`.

**Rationale:** A single spatial snapshot gives a rank-1 sample covariance regardless of the
true source structure — a well-known failure mode for MUSIC (see `docs/architecture.md`). A
common per-chirp Doppler phase multiplying the whole snapshot vector cancels in the outer
product (`(a*x)(a*x)^H = |a|^2 x x^H`), so averaging across the frame's chirps at a fixed range
bin gives a low-variance covariance estimate without needing the target's angle or velocity
known in advance. If two targets sharing a range bin turn out not to decorrelate sufficiently
across chirps, spatial smoothing over adjacent range bins is the fallback (not implemented,
flagged for later if needed).

**Alternatives considered:** Single-snapshot MUSIC (rejected — rank-deficient); spatial
smoothing as the primary method (kept in reserve rather than primary, since it discards
along-array aperture and is only needed for fully coherent same-bin sources).

**Consequences:** `music_spectrum.m` takes a `[Nrx x Nsnapshots]` matrix, not a single vector;
the orchestration script is responsible for assembling snapshots as described above.

---

## D8 — CFAR edge handling differs by axis

**Decision:** On the Doppler axis (circular/periodic due to the DFT), CFAR training/guard
windows wrap around. On the range axis (not physically periodic), edge cells use a shrinking
window (fewer training cells, with the threshold formula's `Ntrain` adjusted accordingly)
rather than wrapping or zero-padding.

**Rationale:** Doppler wrap-around is physically correct (a target just past +v_max is the same
FFT bin structure as one just past -v_max). Wrapping the range axis would let training cells
from very different ranges — with very different clutter/noise statistics — contaminate the
threshold estimate at near/far edges, which is physically wrong.

**Consequences:** `ca_cfar_1d.m`/`ca_cfar_2d.m` take the axis semantics (circular vs. bounded)
as an explicit parameter rather than assuming one behavior for both dimensions of the 2D case.

---

## D9 — No hard dependency on Phased Array System Toolbox for core algorithms

**Decision:** CA-CFAR and MUSIC/DBF are implemented from scratch in `functions/detection/` and
`functions/angle/` using base MATLAB plus Signal Processing Toolbox for windowing. Phased Array
System Toolbox objects (`phased.CFARDetector`, `phased.MUSICEstimator`) are used, if at all,
only as an optional cross-check, never as the primary implementation.

**Rationale:** Implementing these by hand makes the underlying algorithm visible rather than
hidden behind a toolbox call — the point of the exercise. It also keeps the toolbox
requirement minimal: base MATLAB plus Signal Processing Toolbox, which most reviewers running
this code will already have, rather than a less common Phased Array System Toolbox license.

**Consequences:** Toolbox requirement list stays minimal (see `docs/parameter_reference.md`).

---

## D10 — Simplified attenuation model (Phase 1-6), not full radar range equation

**Decision:** Target return amplitude uses a fixed reflectivity/attenuation scalar combined
with a simplified Friis-style `1/R^2` (two-way `1/R^4` in power) path-loss factor, rather than
the full monostatic radar range equation (explicit RCS in m^2, antenna gain, receiver noise
figure in physical units, etc.).

**Rationale:** A full link budget adds real-unit RCS/antenna/noise-figure parameters without
changing any of the range/Doppler/angle/CFAR algorithms being demonstrated — added complexity
without added verification value at this stage.

**Consequences:** SNR is defined and controlled directly (see D11) rather than derived from a
full link budget — stated explicitly in `docs/parameter_reference.md` so the SNR numbers are
never mistaken for a calibrated physical link budget.

---

## D11 — SNR defined at a specific, stated pipeline stage

**Decision:** "SNR" always refers to a named point in the chain — per-chirp, pre-FFT SNR at the
ADC/beat-signal input, unless explicitly qualified otherwise (e.g. "post-range-FFT SNR",
"post-Doppler-integration SNR"). Coherent-integration gain from the range FFT (~`10*log10(Ns)`)
and Doppler FFT (~`10*log10(Nchirps)`) is reported separately, never folded silently into a
single unqualified "SNR" number.

**Rationale:** An SNR number without a stated reference point is ambiguous — a common source of
confusion in radar work generally.

**Consequences:** Every plot/report that states an SNR value states which stage it's measured
at.

---

## D12 — Hand-rolled AWGN, no Communications Toolbox dependency

**Decision:** Additive noise is generated directly (`randn`-based, scaled from the target SNR
definition in D11) rather than via MATLAB's `awgn` function.

**Rationale:** `awgn` belongs to Communications Toolbox, which isn't otherwise needed anywhere
in this pipeline. Avoiding it keeps the toolbox requirement list to Signal Processing Toolbox
plus optional Phased Array System Toolbox for cross-checks only (D9).

**Consequences:** Noise scaling is implemented once in `functions/utils/add_awgn.m`, with the
SNR convention from D11 documented in its header.

---

## D13 — Repository layout adds `config/` and `tests/`

**Decision:** A `config/` folder centralizes all parameters in one place; `tests/` holds
automated verification scripts.

**Rationale:** Purely organizational. Centralizing parameters in `config/` is what makes "no
duplicated magic numbers" enforceable rather than aspirational.

**Consequences:** None material.

---

## D14 — Carrier round-trip phase term is part of the core signal model (added in Phase 3)

**Decision:** `simulate_target_echo.m` includes the factor `exp(-j*2*pi*fc*tau)` in addition to
the baseband chirp phase term `exp(j*pi*S*(t-tau)^2)`.

**Rationale:** This term is what a real dechirp/stretch-processing receiver produces, because
the transmit and receive signals differ by the round-trip delay `tau` at the carrier
frequency `fc`, not only in their baseband chirp envelope. It has no effect on a
magnitude-only peak search (Phase 1/2), which is why its absence wasn't caught until Phase 3 —
where it turned out to be the dominant source of the slow-time Doppler phase progression, since
`fc` (77 GHz) is roughly four orders of magnitude larger than the beat frequency, so even a
femtosecond-scale per-chirp delay change from target motion produces a significant carrier-phase
rotation across the frame.

**Alternatives considered:** None — this wasn't a design choice but a correction of a
physical-model omission, found by testing during Phase 3.

**Consequences:** `functions/signal/simulate_target_echo.m` was modified after Phase 1/2 had
already passed. Both were re-tested to confirm no regression before the fix was accepted — their
numeric results are unchanged, as expected, since the added term is a per-chirp constant phase
factor invisible to a magnitude-only peak search.

---

## D15 — Windowing adopted before the CFAR-facing FFTs (Phase 4)

**Decision:** `functions/utils/apply_window.m` (Hamming) is applied to the fast-time and
slow-time dimensions before the range/Doppler FFTs feeding the 2D CA-CFAR stage, Phase 4
onward. Phases 1-3 remain unwindowed (rectangular) — this isn't a retroactive change to their
already-verified behavior.

**Rationale:** Running 2D CFAR on an unwindowed Range-Doppler map produced 268 detections for a
3-target scene — not because the false-alarm probability was miscalibrated (a separate
noise-only sweep confirmed empirical Pfa of about 1.8e-4 against a design Pfa of 1e-4, a good
match), but because 258 of those 268 detections lay along the exact range row or Doppler column
of one of the three targets — rectangular-FFT sidelobe leakage from a strong target (unwindowed
sidelobes decay only as ~1/n) exceeding the local CFAR threshold well away from the target
itself. Applying a Hamming window before both FFT stages reduced this to 46 total detections (a
5.8x reduction) while still detecting all three targets, at the standard cost of a slightly
widened mainlobe.

**Alternatives considered:** Reducing the injected targets' dynamic range so this never
surfaces (rejected — it would hide a real, instructive phenomenon that real radar returns
commonly show); a stronger taper such as Blackman/Taylor (noted as a possible refinement if a
residual ~6.5x-over-design empirical Pfa needs further reduction, at extra resolution cost — not
adopted by default).

**Consequences:** `range_fft.m`/`doppler_fft.m` are unmodified — pure FFT plus axis conversion,
no implicit windowing. Windowing is applied explicitly by the caller, so the earlier,
unwindowed results are unaffected. The same `apply_window.m` could be adopted for angle-spectrum
sidelobe control if the same phenomenon shows up there for closely-spaced or unequal-strength
targets.

---

## D16 — MUSIC's coherent-source limitation confirmed empirically (Phase 5)

**Decision:** Multi-target MUSIC test scenarios always give co-range-bin targets distinct
velocities; `build_array_covariance.m`'s header documents this as a hard requirement of the
chosen covariance-estimation strategy, not a suggestion.

**Rationale:** D7's outer-product-averaging covariance estimator relies on each source's
per-chirp phase progression to decorrelate it from other sources across the frame's chirps. The
first two-target resolution test used two stationary targets (v=0 for both) 6 degrees apart, and
the resulting covariance showed only one dominant eigenvalue (3.1e6), with the second-largest
eigenvalue (29.3) indistinguishable from the noise floor (13-27) — a rank-1 signal subspace
despite two physically distinct targets. Root cause: two stationary co-range-bin targets produce
an identical combined per-chirp snapshot vector on every chirp (no Doppler-driven decorrelation),
so averaging their outer products across chirps can't separate them — the "coherent source"
failure mode D7 anticipated, now confirmed directly. Giving the two targets small, distinct
velocities (+2/-2 m/s) restored a proper two-dominant-eigenvalue structure (2.08e6, 3.08e5 vs.
noise eigenvalues 14-28), and MUSIC then resolved both angles exactly, while conventional
(Bartlett) beamforming showed only one broad, merged peak.

**Alternatives considered:** Spatial smoothing (kept as the fallback in D7 for genuinely
coherent same-range-bin, same-Doppler sources, e.g. multipath) — not needed here since assigning
distinct velocities is physically natural for two separate targets and is simpler.

**Consequences:** Any scenario with two or more targets sharing a range bin needs distinct
velocities for MUSIC to resolve them with this covariance strategy — a documented limitation,
not silently worked around.

---

## D17 — Covariance transpose/conjugation bug in `build_array_covariance.m`

**What happened:** While building the full multi-target pipeline (Phase 6), the angle estimates
for all 4 4-target targets came out **exactly sign-flipped** about broadside (e.g. true
-25.00 degrees -> estimated +25.00 degrees; true 10.00 -> -10.00). Diagnosed methodically rather
than patched blindly:

1. Isolated to a single stationary target, outside the clustering/association logic — still
   flipped, ruling out that code.
2. Reproduced with and without Hamming windowing — identical flip either way, ruling out D15's
   windowing.
3. Re-derived the array covariance formula from first principles
   (`R_hat = (1/Nchirps) * sum_m x_m x_m^H`) and compared it symbol-by-symbol against
   `build_array_covariance.m`'s actual code.

**Root cause:** with `snapshots` organized as `Nchirps x Nrx` (chirp snapshots as rows), the
target formula `R_hat = (1/Nchirps) * sum_m x_m x_m^H` is produced by
`snapshots.' * conj(snapshots)` (plain transpose contracted against an elementwise conjugate) —
**not** by `snapshots' * snapshots` (MATLAB's conjugate-transpose-then-multiply), which computes
the full conjugate of the intended matrix. This is a classic samples-as-rows vs.
samples-as-columns transpose pitfall: the familiar "R = X*X^H" covariance formula assumes X has
snapshots as columns, and applying it unchanged to a samples-as-rows matrix silently produces the
conjugated (angle-mirrored) result. For this project's ULA steering vector
`a(theta) = exp(j*2*pi*d*n*sin(theta)/lambda)`, using the conjugate covariance is mathematically
equivalent to mirroring every angle estimate about broadside.

**Fix:** `functions/angle/build_array_covariance.m`: changed
`R_hat = (snapshots' * snapshots) / Nchirps;` to
`R_hat = (snapshots.' * conj(snapshots)) / Nchirps;`, with an expanded comment explaining the
transpose convention. `music_spectrum.m` needed no change — the bug was entirely in how `R_hat`
was constructed upstream, not in the eigendecomposition or spectrum evaluation.

**Validation:** re-ran the full scenario after the fix — all 4 targets now resolve to the
correct sign, matching ground truth to grid resolution (0.00 degree error at a 0.05-degree-step
grid, since the 4 chosen test angles land on grid points; range/velocity errors unchanged at
0.03-0.17 m / 0.04-0.17 m/s, as expected since this bug never touched range/Doppler processing).

---

## D18 — `dechirp_mix.m` broadcasting error on chirp-train input

**Status: FIXED.** Found while running the Range-Doppler stage (Phase 3) for the first time
with multi-chirp input.

**Symptom:**
```
Error using .*
Arrays have incompatible sizes for this operation.
Error in dechirp_mix (line 28)
```

**Root cause:** `dechirp_mix.m` was originally written for two matched-shape `1 x Ns` row
vectors: `beat = tx .* conj(rx)`. Once chirp trains were introduced, `rx` becomes an
`Ns x Nchirps` matrix while `tx` remains the `1 x Ns` row from `generate_chirp.m`. MATLAB's
implicit broadcasting requires each dimension to match or be singleton: dimension 1 (1 vs. `Ns`)
broadcasts fine, but dimension 2 (`Ns` vs. `Nchirps`) matches neither condition, so MATLAB
correctly refused the operation.

**Fix:** `dechirp_mix.m` now branches on shape: if `rx` is a vector matching `tx`'s shape (the
original single-chirp case), behavior is unchanged (`beat = tx .* conj(rx)`). Otherwise (the
`Ns x Nchirps` chirp-train case), it broadcasts `tx` as a column explicitly
(`beat = tx(:) .* conj(rx)`). No call site needed to change — the fix is centralized in the one
shared function.

**Also checked:** every other `dechirp_mix(` call site in the repository passes a `1 x Ns` row
vector matching `tx`'s shape, so they're unaffected by this change.

---

## D19 — Missing Pfa-vs-threshold-factor sweep in Phase 4

**Status: FIXED.** The CFAR stage needs to show empirical Pfa tracked against several design Pfa
values as a sweep — this was missing from `src/phase4_cfar_detection.m`, which only computed a
single empirical Pfa from the small 3-target windowed scenario.

**Fix:** added a dedicated section to `src/phase4_cfar_detection.m`: a fresh noise-only
`Ns x Nchirps` map (via the same `add_awgn`/`range_fft`/`doppler_fft` chain used elsewhere), run
through `ca_cfar_2d` at each of four design Pfa values (1e-2, 1e-3, 1e-4, 1e-5), printing
empirical Pfa and the raw false-alarm/cell counts at each.

**Result:** empirical Pfa tracked design Pfa across all four decades (1e-2 -> 9.75e-3,
1e-3 -> 1.19e-3, 1e-4 -> 1.83e-4, 1e-5 -> 3.05e-5).

**Also confirmed while re-checking Phase 4 end to end:** the 1D CFAR-flagged bins matched the
expected target positions exactly (`[19.908, 20.025, 34.898, 35.015, 50.004]`). The 2D
unwindowed/windowed detection counts and false-alarm rates vary run to run with the random noise
seed — expected for small-sample false-alarm counts, and not a bug, as long as the
high-SNR target-bin detections stay deterministic (they do).

---

## D20 — `uitable` in the Phase 6 summary figure silently dropped by `exportgraphics`

**Status: FIXED.** MATLAB's own warning surfaced this: `Warning: UI components will not be
included in the output. To include UI components, use the 'exportapp' function.`

**Symptom:** `functions/plotting/plot_full_scenario.m` built its right-hand summary panel with
`uitable`, then saved the figure with `exportgraphics`. `exportgraphics` captures graphics
objects (axes, lines, images, text) but not UI components (`uitable`, `uicontrol`) — a documented
MATLAB limitation. The practical effect: every copy of `results/06_full_scenario_summary.png`
generated before this fix has its entire right-hand summary table missing, leaving only the
Range-Doppler map panel. Since this is the pipeline's main figure, that's a real defect in the
deliverable, not a cosmetic one.

**Fix:** replaced the `uitable` block with a plain-text table drawn via `text()` on the same
`axis off` subplot — fixed-width columns in a monospace font, which is a graphics object and
exports correctly. Also added the mean range/velocity/angle error summary line beneath the
table, previously only printed to console.

**Follow-up:** the first `text()`-based table used a fixed character width that turned out to
overflow the figure's right edge and get clipped on some runs, since the actual rendered width of
a monospace string depends on font substitution and DPI, which vary by machine. Fixed properly by
drawing the text once, measuring its actual rendered `Extent` (MATLAB's true on-screen bounding
box), and programmatically reducing font size in a loop until it provably fits within the axes —
correct by construction rather than tuned to one screenshot. A warning is emitted if even the
minimum readable font size doesn't fit, so a future run surfaces the problem rather than silently
clipping.

---

## D21 — Wrong HDF5 stream name and axis order assumed for the real dataset (Phase 7)

**Status: FIXED.** Found on the first real run of `src/phase7_dataset_validation.m` against
`indoor_sample_50.h5`.

**Symptom:** `Expected an 'adc' dataset ... but did not find one. Found datasets: depth,
depth_timestamp, radar, radar_timestamp, rgb, rgb_timestamp`.

**Root cause #1 (stream name):** the code assumed a literal HDF5 key named `adc`, based on
descriptive documentation ("raw ADC samples") rather than the file's actual key names. Checking
the RaDICaL SDK's own README confirmed the raw radar array is stored under the key `radar`, and
is raw pre-FFT ADC data — `adc` was never a literal key, just how the data was described
elsewhere. Fixed: the script now looks for `radar`.

**Root cause #2 (axis order, found by code review while fixing #1):** the frame-selection logic
assumed the frame index was always the array's first dimension. The real file's `radar` dataset
has shape `[304, 8, 32, 50]` — the frame axis (50) is actually last, not first. The old
axis-identification heuristic matched a "slow-time" axis by proximity to a documented
`Nchirps=64`; since the real chirp axis is 32 (see root cause #3) but the frame axis is 50, and
|50-64| < |32-64|, that heuristic would have misidentified the frame axis as the chirp axis — a
more severe, silent error, caught only by careful code review while making the first fix. Fixed:
every axis (fast-time, antenna, frame, chirp) is now identified by matching it against a
distinctive, independently known count (Ns=304, numTx*numRx=8, this sample's own 50 frames),
with chirp assigned as whatever is left over — order-independent by construction.

**Root cause #3 (chirps-per-frame value, found once axis identification was fixed):** the real
file has 32 chirps/frame, not the 64 documented on the SDK's generic configuration page — that
page most likely documents a different RaDICaL recording configuration, not this specific
50-frame indoor sample. The script now compares the two, prints an explicit note when they
differ, and uses the actually observed value (32) — along with recomputed `v_max`/`dv`, which
depend on it — for all Doppler processing. Leaving the stale documented value in place wouldn't
have errored; it would have zero-padded a real 32-chirp burst to a 64-point grid and quietly
reported a velocity axis that didn't match the real acquisition.

**Also updated:** `docs/dataset_notes.md`'s stream-name description and hardware-parameter table
to match the corrected code.

---

## D22 — Complex ADC samples arrive as a MATLAB struct, not a numeric array (Phase 7)

**Status: FIXED.** Found immediately after D21, once axis identification was working: the script
failed inside `apply_window.m` with `Invalid data type. Argument must be numeric, char, or
logical`.

**Root cause:** HDF5 has no native complex-number type. The RaDICaL capture tooling stores a
complex array as a compound HDF5 type — a struct-like record with two real-valued fields (`r`/
`i`) — rather than fail to represent it. MATLAB's `h5read` faithfully returns such a compound
dataset as a MATLAB struct, not a native numeric array, so the first arithmetic operation on it
failed.

**Fix:** immediately after `h5read`, the script checks `isstruct(frame_cube)`; if true, it
identifies the real/imaginary member fields by name (checking `r`/`real`/`re` and `i`/`imag`/
`im`, case-insensitively) and reassembles a proper MATLAB `complex()` double array before any
further processing. If the compound type's field names don't match any expected convention, the
script raises an explicit error naming the actual fields found, rather than guessing.

---

## D23 — Phase 7b: MTI clutter cancellation and calibrated CFAR for real data

**Status: FIXED, verified.** An optional, additive extension
(`src/phase7b_dataset_validation_mti_cfar.m`) addressing Phase 7's own disclosed limitation: CFAR
reused the synthetic scenario's design Pfa unmodified, never re-tuned for RaDICaL's real indoor
clutter statistics, which produced a 16-cell static-clutter ridge plus a leakage spike at zero
Doppler among Phase 7's 19 detection clusters. Phase 7 itself wasn't modified — this is a
separate script, so both the raw and clutter-suppressed pipelines remain independently runnable
and comparable.

**Design (first version):** (1) a zero-Doppler MTI stage — subtracting each range bin's own mean
across the frame's chirps (after windowing, so the null lands exactly on the fftshift-centered
v=0 bin) — to cancel static returns, which are constant chirp-to-chirp by definition; (2) an
empirical CFAR Pfa calibration using this recording's own measured false-alarm rate at
|v| > 5 m/s (a Doppler band far above any plausible indoor walking speed), selecting the least
restrictive candidate Pfa that still measured zero false alarms there.

**First result: a regression.** Raw CFAR detections went from 93 (Phase 7) to 117, with 17 of 19
clustered detections landing at exactly +/-1 Doppler bin from zero across nearly the whole range
axis — a wider clutter smear than before. Root cause: (1) subtracting a range bin's mean across
chirps zeroes only the exact k=0 DFT bin — a basic Fourier property, it mathematically cannot
touch any other bin. A Hamming window over 32 chirps has a mainlobe roughly 4 bins wide, so a
near-static reflector's energy was never confined to bin 0 alone; the mainlobe skirt was
untouched. (2) The Pfa calibration only tested far from any clutter (|v| > 5 m/s), never near the
clutter mainlobe's skirt, where CA-CFAR's known clutter-edge-masking limitation actually shows up
— so it picked a Pfa 10x more lenient than the design value, which over-triggered exactly where
it mattered.

**Fix (second version):** (a) an explicit minimum-detectable-velocity (MDV) blind zone — masking
out any CFAR flag within +/-2 Doppler bins of zero, sized from the Hamming window's own known
mainlobe half-width — since detection that close to a clutter mainlobe is fundamentally
unreliable regardless of Pfa (the standard "blind speed" concept in real MTI radar); (b) the Pfa
calibration's reference region extended to also include a clutter-skirt band (3-5 bins from
zero, outside the blind zone), requiring zero measured false alarms in both regions before a
candidate Pfa is accepted.

**Second result: verified.** Raw detections dropped from 93 to 6; clustered detections from 19
to 2. Both surviving clusters are the same off-axis detections identified in every prior run as
the most likely genuine moving target (R=4.56-4.89 m, v around -1.86 m/s). The leakage spike and
the static-clutter ridge are gone. No tested Pfa candidate reached zero false alarms in both
reference regions, so the most stringent candidate tested (1e-6) was used, with its nonzero
residual (6 false alarms, empirical Pfa ~3.9e-3 in the clutter-skirt region) reported rather than
hidden. This selection rule never inspects final detection counts, only the calibration
measurements — the clean outcome wasn't reverse-engineered from a desired answer.

**Disclosed caveats:**

- Even at the strictest tested Pfa, the clutter-skirt region still shows a nonzero measured
  false-alarm rate — a real residual risk, not proof the skirt is clean on every frame.
- The two surviving detections now share the identical peak Doppler bin, where every earlier run
  split them across two adjacent bins — a minor discretization shift from the MTI demeaning, not
  a new finding.
- Single-frame (frame 1 of 50) validation only — not a multi-frame confirmation that this
  calibration generalizes across the recording.
- The MDV blind zone means a genuinely near-stationary target (|v| <= 1.24 m/s) would also be
  suppressed — a standard, disclosed MTI trade-off, not a defect.

---

## D24 — Phase 7b's figure didn't match its own written description

**Status: FIXED.** During final review before publishing, I compared the actual
`results/07b_dataset_validation_clutter_suppressed.png` against its own gate report's claim that
"the figure shows only the two red-circled detections against an otherwise clean map." The image
still showed a bright leakage spike near 0.08 m and clutter bands across the range axis near
|v| ~ 0.5-1 m/s — the detections were right, but the description of the figure was an overclaim.

**Root cause:** subtracting a range bin's mean across chirps zeroes only the exact center (v=0)
Doppler bin — it can't touch the Hamming window's ~4-bin-wide mainlobe skirt, which still carries
real clutter/leakage energy in the bins immediately around center. The detection logic already
excludes that skirt via the MDV blind zone (D23), but that exclusion was applied only to the
detection map, never to the power map handed to the plotting function for display — so the
figure's background still showed the same raw clutter/leakage energy CFAR was never claiming to
have removed, just with detections suppressed on top of it.

**Second issue found in the same figure:** `functions/plotting/plot_dataset_validation.m`'s title
was hardcoded to "Phase 7 -- REAL-DATA Validation...". Phase 7b reused this function unmodified
(to avoid duplicating plotting code), so its own figure was mislabeled as a Phase 7 result.

**Fix:** `plot_dataset_validation.m` gained an optional `title_lines` argument — when omitted,
behavior for the existing Phase 7 caller is unchanged. `phase7b_dataset_validation_mti_cfar.m`
now (a) sets the MDV blind zone's columns in the displayed power map to the plot's own -40 dB
floor before plotting, so the figure honestly shows "no detection claim made here" instead of raw
clutter power in a zone the algorithm already excludes, and (b) passes an explicit "Phase 7b"
title. Neither change touches any detection, cluster, or reported number — display only.

**Validation:** re-ran the script; the regenerated figure shows a clean background in the MDV
blind zone, the two correct detections, and the corrected title.
