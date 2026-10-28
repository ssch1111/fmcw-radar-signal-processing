# Methodology

This document explains the theory, equations, and design decisions behind this project's FMCW
radar signal-processing pipeline. It is written to demonstrate the reasoning behind each stage,
not just restate textbook formulas — where this project's specific implementation choices
matter (timing conventions, sign conventions, covariance formulas), that is called out
explicitly, with references to the dated decisions in `docs/engineering_decisions.md` where a
real bug was found and fixed during development.

Parameter values referenced throughout are this project's synthetic-scenario baseline
(`config/get_radar_params.m`): 77 GHz carrier, 1 GHz sweep bandwidth, 40 µs active chirp / 20 µs
idle (60 µs repetition interval), 20 MHz ADC rate, 128 chirps/frame, 8-element receive array.
Phase 7's real-data parameters (`config/get_radical_dataset_params.m`) differ (documented in
`docs/dataset_notes.md`) but use the identical formulas below.

## 1. FMCW fundamentals

A Frequency-Modulated Continuous Wave (FMCW) radar transmits a signal whose instantaneous
frequency sweeps linearly over time (a "chirp") rather than a single fixed frequency. Because
the transmitted frequency at any instant is known exactly, the time delay to a target — and
therefore its range — can be recovered from a FREQUENCY difference rather than a much harder
time-of-flight measurement, which is what makes FMCW practical for compact, low-cost radar
(automotive, industrial, and short-range sensing) compared to pulsed radar.

This project implements a **sawtooth** (single-direction ramp, then reset) linear chirp rather
than a triangular one (decision D1, `docs/engineering_decisions.md`) — sawtooth is simpler to
reason about and is what most single-chip automotive radars (including the TI-class chip behind
the Phase 7 dataset) actually use, at the cost of requiring the transmitter to "fly back" to the
start frequency between chirps (the idle time, below).

## 2. Chirp parameters

For a chirp of active duration `T_chirp` sweeping bandwidth `B`, the chirp SLOPE is

```
S = B / T_chirp        [Hz/s]
```

This project deliberately keeps two separate timing quantities (decision D2), rather than
treating them as one:

- `T_chirp_active` — the duration of the actual linear frequency ramp (40 µs baseline).
- `T_idle` — dead time after the ramp before the next one starts (20 µs baseline), during which
  the transmitter resets to the start frequency and the ADC is not necessarily sampling.
- `T_CRI = T_chirp_active + T_idle` — the Chirp Repetition Interval, i.e. the actual time between
  the start of one chirp and the start of the next.

This distinction matters because **range-related quantities use `T_chirp_active`/`S`, while
Doppler-related quantities use `T_CRI`** — conflating the two (a common simplification in
introductory treatments) would make the Doppler-frequency-to-velocity conversion wrong by a
factor of `T_CRI/T_chirp_active` (here, 1.5×) whenever idle time is non-negligible relative to
the active ramp, as it is in this project's baseline.

## 3. Beat signal formation

A target at range `R` reflects the transmitted chirp back with round-trip delay `tau = 2R/c`.
Mixing ("dechirping" or "stretch processing") the received echo against a replica of the
transmitted chirp produces a **beat signal** whose frequency is directly proportional to that
delay (and therefore to range):

```
f_beat = S * tau = 2*R*S/c
```

The mixing operation is a complex multiply. This project uses complex (I/Q) baseband
representation throughout (decision D3), not a real-valued signal, specifically so that a
**Doppler-shifted beat signal's sign is preserved** — a real-valued/magnitude-only
representation cannot distinguish a target approaching from one receding, which this project's
Phase 3 explicitly needs to demonstrate.

**Sign convention (decision D4):** this project defines the beat signal as

```
beat = tx .* conj(rx)
```

which yields `f_beat = +S*tau` (positive) for a target at positive range under this project's
up-chirp convention. This was **not the first attempt** — an initially-implemented
`rx .* conj(tx)` gave the numerically-correct magnitude but the WRONG SIGN, caught during Phase
1 by checking the beat signal's closed-form instantaneous frequency independently of the FFT
(which cannot see sign for a symmetric power spectrum), not just by eyeballing an FFT peak. See
`docs/engineering_decisions.md` D4 for the full correction record — this is exactly the kind of
sign-convention detail introductory material often glosses over and that this project checked
explicitly rather than assumed.

The full modeled echo also includes a **carrier round-trip phase term** `exp(-j*2*pi*fc*tau)`
in addition to the baseband chirp envelope's own phase — this term is invisible to a
magnitude-only range check (Phases 1-2) but is the DOMINANT source of the slow-time Doppler
phase progression a moving target produces (decision D14; `fc` is ~4 orders of magnitude larger
than the beat frequency, so a sub-picosecond per-chirp change in `tau` from target motion still
produces a significant carrier-phase rotation across a frame). Omitting this term was a real
bug found during Phase 3 development (a moving target showed zero measured Doppler) — see
`docs/engineering_decisions.md` D14.

## 4. Range estimation

Once the beat frequency is measured (via FFT, below), range follows directly from the same
relationship used to derive the beat frequency:

```
R = f_beat * c / (2*S)
```

**Range resolution** — the minimum range separation at which two targets produce distinguishable
FFT peaks — depends only on the swept bandwidth, not on the chirp duration or sample rate:

```
dR = c / (2*B)
```

This project's baseline (`B` = 1 GHz) gives `dR` ≈ 0.150 m. Phase 2 explicitly demonstrated this
by placing two targets exactly `1*dR` apart and confirming they are resolved as two distinct FFT
peaks (with a measurable dip between them), not merely asserting the formula.

**Maximum unambiguous range** follows from the ADC's Nyquist limit on the beat frequency it can
represent without aliasing:

```
R_max = Fs * c / (4*S)
```

(the factor of 4 rather than 2 comes from the Nyquist criterion `f_beat,max = Fs/2` substituted
into `R = f_beat*c/(2S)`).

## 5. Doppler processing

A target's radial velocity `v` shifts the phase of its beat signal by a small amount from one
chirp to the next (via the carrier round-trip phase term above), even though the target's range
barely changes within one chirp — this project uses the **stop-and-hop approximation**
(decision D6: treat range as constant WITHIN a chirp, but advance it chirp-to-chirp as
`R(m) = R0 + v*(m-1)*T_CRI`), valid here because the target's motion during one active chirp
(tens of µs) is negligible compared to the range resolution (a margin of roughly 230× at this
project's maximum test velocity — quantified explicitly in `docs/engineering_decisions.md`, not
just asserted).

A second FFT — the **Doppler FFT** — taken across the SLOW-TIME dimension (one sample per chirp,
at a fixed range bin) recovers this phase progression as a frequency:

```
f_d = 2*v/lambda
```

**Maximum unambiguous velocity** (Nyquist on `f_d`, sampled once per `T_CRI`):

```
v_max = lambda / (4*T_CRI)
```

**Velocity (Doppler) resolution**, from the frequency resolution of an `Nchirps`-point DFT:

```
dv = lambda / (2*Nchirps*T_CRI)
```

Phase 3 tested a stationary target (v=0) and both a positive and negative velocity, confirming
correct SIGN recovery in both cases (a real risk if the complex-baseband/carrier-phase
convention above were inconsistent) as well as range and velocity error within one FFT bin of
the injected ground truth.

## 6. Range-Doppler maps

Applying the range FFT to every chirp in a frame (columns of an `Ns x Nchirps` beat-signal
matrix) and then the Doppler FFT across chirps (rows) produces a 2-D **Range-Doppler (RD) map**:
each cell represents the received energy at a specific (range, velocity) combination. This is
the standard representation CFAR detection (below) operates on. This project fftshifts the
Doppler axis so zero-Doppler sits at the center, matching how RD maps are conventionally
displayed and making a stationary vs. moving target visually obvious.

## 7. CFAR (Constant False Alarm Rate) detection

A fixed amplitude threshold cannot work reliably in the presence of varying noise/clutter
power — too low and it drowns in false alarms where noise is strong, too high and it misses
real targets where noise is weak. **Cell-Averaging CFAR (CA-CFAR)** instead estimates the LOCAL
noise level around each cell under test (CUT) from a window of nearby "training" cells (skipping
a small "guard" region immediately around the CUT, so the target's own energy doesn't
contaminate the noise estimate), and sets a threshold proportional to that local estimate:

```
threshold = alpha * noise_estimate
alpha = n * (Pfa^(-1/n) - 1)
```

where `n` is the number of training cells actually used and `Pfa` is the design false-alarm
probability (this `alpha` formula is the standard result for exponentially-distributed
(power-domain, complex-Gaussian-noise) cell statistics). This project implements CA-CFAR in
both 1-D (a range profile) and 2-D (a full Range-Doppler map) forms, with configurable
guard/training cell counts and Pfa (`config/get_radar_params.m`).

**Edge handling (decision D8):** the Doppler axis is treated as PERIODIC (circular wraparound,
matching the DFT's own periodicity), while the range axis is treated as NON-PERIODIC (a
shrinking/clipped training window near range-axis edges, since range has no physical
"wraparound").

Phase 4 does not just show CFAR succeeding — it explicitly demonstrates two well-known
limitations, reproduced and explained rather than only asserted:

- **Clutter-edge effect:** a target whose training window straddles a step change in background
  clutter level gets an inflated noise estimate (and therefore a higher threshold) purely from
  the edge, independent of the target's own strength.
- **Mutual masking:** a weak target near a much stronger one has its threshold inflated by the
  strong target's energy falling inside its training window, and can be missed entirely — verified
  by comparing the same weak target's detectability with and without the strong neighbor present.

A real, initially-surprising finding during Phase 4 development: an UNWINDOWED (rectangular-FFT)
Range-Doppler map showed roughly 40× more CFAR detections than the number of injected targets.
Diagnosis (checking whether the extra detections lay along a target's own range/Doppler
row/column, i.e. its FFT sidelobes, vs. scattered randomly) confirmed this was rectangular-FFT
spectral leakage, not a broken threshold — the CFAR calibration itself was separately confirmed
correct via a noise-only Monte Carlo sweep across four decades of design Pfa. The fix (decision
D15) was applying a Hamming window before CFAR-facing FFTs, at the standard cost of a slightly
widened mainlobe.

## 8. Angle estimation

A Uniform Linear Array (ULA) of `Nrx` receive elements, spaced `d` apart, sees a plane wave
arriving from angle `theta` (measured from broadside) with a per-element phase progression
described by the **array steering vector**:

```
a_n(theta) = exp(j*2*pi*d*n*sin(theta)/lambda),   n = 0..Nrx-1
```

evaluated at the CARRIER wavelength (not the instantaneous chirp frequency), valid because array
combining happens on the already-dechirped beat signal and the swept bandwidth is negligible
compared to the carrier frequency (no beam squint). This project uses `d = lambda/2`
(half-wavelength spacing) specifically to avoid grating lobes across its full ±60° field of
view — a wider spacing would fold distant angles onto each other unresolvably.

## 9. MUSIC vs. conventional beamforming

**Conventional (Bartlett/delay-and-sum) beamforming** scans a candidate angle grid and, for each
angle, coherently sums the array's steering-compensated outputs:

```
P_DBF(theta) = a(theta)^H * R * a(theta)
```

where `R` is the array's spatial covariance matrix. Its angular resolution is fundamentally
limited by the array's physical aperture (beamwidth ~ `lambda/(Nrx*d)` radians) — two closely
spaced targets within that beamwidth appear as one broad, unresolved peak.

**MUSIC (MUltiple SIgnal Classification)** exploits the fact that, for `Nsources` incoming
signals on an `Nrx`-element array (`Nrx > Nsources`), the array covariance's eigen-decomposition
splits cleanly into a `Nsources`-dimensional SIGNAL subspace (large eigenvalues) and an
`(Nrx-Nsources)`-dimensional NOISE subspace (small eigenvalues, ideally all equal to the noise
floor). Because the true steering vectors are, by construction, ORTHOGONAL to the noise
subspace, scanning

```
P_MUSIC(theta) = 1 / ( a(theta)^H * En * En^H * a(theta) )
```

(where `En` holds the noise-subspace eigenvectors) produces sharp peaks exactly at the true
angles, with resolution not fundamentally limited by aperture the way DBF is — the basis for
this project's Phase 5 demonstration of MUSIC resolving two targets 6° apart that conventional
DBF shows as a single broad peak.

**Covariance estimation** (`functions/angle/estimate_covariance.m`) averages the outer product
of each chirp's array snapshot across the frame:

```
R_hat = (1/Nchirps) * sum_m  x_m * x_m^H
```

**A real, non-obvious implementation bug was found and fixed here (decision D17):** with the
per-chirp snapshots stored as ROWS of an `Nchirps x Nrx` matrix (`x_m` = row `m`), the formula
above is produced by `snapshots.' * conj(snapshots)` — plain transpose contracted against an
elementwise conjugate — and NOT by the more natural-looking `snapshots' * snapshots`
(conjugate-transpose-then-multiply), which instead computes the full CONJUGATE of the intended
covariance. Because this project's steering vector satisfies `conj(a(theta)) = a(-theta)`, using
the conjugated covariance silently mirrors every downstream angle estimate about broadside — a
bug that produced perfect range/velocity but exactly-sign-flipped angles, caught by re-deriving
the covariance formula from first principles and comparing it symbol-by-symbol against the code.
See `docs/engineering_decisions.md` D17 for the full diagnosis and fix.

**Coherent-source limitation (decision D7/D16):** this covariance estimator relies on each
source's per-chirp phase PROGRESSION to decorrelate it from other sources across the averaging
ensemble. Two STATIONARY targets sharing a range bin produce an IDENTICAL snapshot on every
chirp, which no amount of averaging can separate — confirmed empirically in Phase 5 (a rank-1
covariance where two sources were expected) and fixed, as a permanent scenario-construction
constraint, by giving co-range-bin multi-target test scenarios distinct velocities.

## 10. Multi-target integration (Phase 6)

The full pipeline — per-element beat synthesis, windowed range+Doppler FFT, non-coherent power
summation across elements for detection, 2-D CA-CFAR, clustering of adjacent detected cells into
one detection per physical target (`functions/detection/cluster_detections.m`), per-detection
MUSIC angle estimation, and nearest-range association back to ground truth for reporting
(`functions/detection/associate_detections.m`) — is exercised together on a 4-target scenario
spanning distinct ranges, velocities, AND angles (Phase 6, the main integration result). This
validates that the phases genuinely compose: each stage consumes the previous stage's actual
output (checked explicitly for every phase), not independently-regenerated data that would look like integration
without actually being it.

The association step is intentionally simple (greedy nearest-neighbor by range with a small
gate) and its limitation is stated rather than hidden: it has no tie-breaker if two targets fall
within the gate distance of each other in range alone (not exercised by the current
well-separated scenario).

## 11. Real-data validation (Phase 7)

Synthetic validation (Phases 1-6) has the unique advantage that the true target range,
velocity, and angle are known EXACTLY, because this project generated them — every reported
"error" is a genuine measurement against ground truth. Real recorded data has no such luxury:
there is no channel through which the exact true state of a human subject moving through a room
was independently, precisely measured at the same time as the radar recording. Phase 7
therefore validates a DIFFERENT, weaker but still meaningful thing: that this project's own
processing code, unmodified, produces INTERNALLY CONSISTENT, PHYSICALLY PLAUSIBLE results when
given real ADC samples instead of synthetic ones — correct bin widths and ambiguity limits for
the real radar's actual (different) timing parameters, and detections that fall within the
recording scenario's physically sensible range window, rather than an exact numerical error
against a known answer. This distinction is stated explicitly in
`src/phase7_dataset_validation.m`'s own header, precisely
so a reader cannot mistake Phase 7's validation for the same kind of exact check Phases 1-6
perform.

See `docs/dataset_notes.md` for the dataset's source, licence, and current execution status.
