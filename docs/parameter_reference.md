# Parameter Reference

Baseline parameter values for the synthetic scenario (`config/get_radar_params.m`), chosen for
internal consistency and physical realism. All values are in SI base units internally (Hz, m, s,
m/s, radians); degrees are used only at the plotting/reporting boundary.

## 1. RF / waveform parameters

| Symbol | Meaning | Value | Rationale |
|---|---|---|---|
| `fc` | Carrier frequency | 77 GHz | Standard automotive/mmWave band (76-81 GHz). |
| `B` | Sweep bandwidth | 1 GHz | Mid-tier automotive-radar bandwidth; drives range resolution. |
| `Tchirp_active` | Active linear-ramp duration | 40 us | Typical automotive chirp ramp time; kept distinct from `T_CRI` (see D2). |
| `T_idle` | Idle/retrace time between ramps | 20 us | Realistic ADC settle/synthesizer retrace allowance (non-zero, per D2). |
| `T_CRI` | Chirp repetition interval = `Tchirp_active + T_idle` | 60 us | Used in all Doppler formulas. |
| `S` | Chirp slope = `B / Tchirp_active` | 25 MHz/us (2.5e13 Hz/s) | Matches typical real automotive chirp slopes (~20-70 MHz/us). |
| `lambda` | Wavelength = `c / fc` | ~3.90 mm | Derived, not independently set. |
| `c` | Speed of light | 2.998e8 m/s | Physical constant. |

## 2. ADC / fast-time sampling

| Symbol | Meaning | Value | Rationale |
|---|---|---|---|
| `Fs` | ADC sample rate (post-dechirp, IF/beat-signal domain) | 20 MHz | Chosen relative to the *beat-frequency* bandwidth of interest, not to `fc` or `B` — see `R_max` below. |
| `Ns` | Samples per chirp = `round(Fs * Tchirp_active)` | 800 | Determines raw range-FFT length before any zero-padding. |
| `Nfft_range` | Range FFT length (zero-padded) | 1024 (next pow2 >= Ns) | Zero-padding interpolates the spectrum for a cleaner peak/plot; it does not improve true resolving power, which stays `dR = c/(2B)`. |

**Derived range limits:**

- Range resolution: `dR = c/(2B) = 0.15 m`
- Max unambiguous range (Nyquist on beat frequency, `f_beat,max = Fs/2`): `R_max = Fs*c/(4*S) = 60 m`

`R_max = 60 m` positions this as a short/mid-range automotive-corner or industrial sensing
scenario. Test target ranges in Phases 1-2 stay well inside this limit (10-45 m) with margin for
the AWGN cases.

## 3. Slow-time / Doppler

| Symbol | Meaning | Value | Rationale |
|---|---|---|---|
| `Nchirps` | Chirps per frame | 128 | Power of two; standard automotive frame size; balances Doppler resolution against frame time. |
| Frame time = `Nchirps * T_CRI` | | 7.68 ms | Reasonable coherent processing interval. |

**Derived Doppler limits:**

- Max unambiguous velocity: `v_max = lambda/(4*T_CRI) ~ 16.2 m/s` (~58.4 km/h)
- Doppler resolution: `dv = lambda/(2*Nchirps*T_CRI) ~ 0.25 m/s`

**Design trade-off:** `v_max` here is modest relative to highway closing speeds (~60 m/s),
because extending `v_max` requires shortening `T_CRI`, which is already constrained by
`Tchirp_active` (40 us) plus a non-zero idle time. This is a genuine trade-off in FMCW frame
design (shorter chirps give higher `v_max` but shorter dwell/lower per-chirp SNR gain; more
chirps give better Doppler resolution but a longer frame time) — it positions the default
scenario as low/moderate-speed (industrial, pedestrian/cyclist-speed, or closing-speed-limited
automotive corner radar).

**Stop-and-hop validity check (D6):** worst-case intra-chirp range change is
`v_max * Tchirp_active ~ 16.2 * 40e-6 ~ 0.65 mm`, which is much smaller than `dR = 150 mm` — the
approximation holds by roughly two orders of magnitude of margin.

## 4. Array / angle

| Symbol | Meaning | Value | Rationale |
|---|---|---|---|
| `Nrx` | Receive elements (ULA) | 8 | More elements improve MUSIC's angular resolution for the resolution-advantage demonstration. |
| `d` | Element spacing | `lambda/2` | Standard half-wavelength spacing; avoids grating lobes over +/-90 degrees. |
| FOV | Angle field of view | +/-60 degrees | Typical short/mid-range automotive corner-radar FOV; avoids the endfire region where a ULA's angular resolution degrades sharply. |

**Narrowband array assumption:** array steering phase is evaluated at `fc` (not at the
instantaneous chirp frequency or at `f_beat`), valid because array combining happens on the
already-dechirped baseband/IF signal, and because `B << fc` (1 GHz vs. 77 GHz) makes beam squint
across the sweep negligible.

## 5. Detection (CA-CFAR)

| Symbol | Meaning | Value | Rationale |
|---|---|---|---|
| `Pfa` | Design false-alarm probability | 1e-4 | Standard baseline value in radar CFAR practice; low enough to keep false alarms rare, high enough to keep threshold loss modest. |
| `Ntrain` (1D) | Training cells per side | 8 | Enough cells for a reasonably stable noise-level estimate without averaging into adjacent targets. |
| `Nguard` (1D) | Guard cells per side | 2 | Prevents target energy leaking into the training average. |
| `Ntrain`, `Nguard` (2D) | Same roles, per axis | 8 / 2 (range axis), 4 / 1 (Doppler axis) | The Doppler axis window is narrower because the Doppler dimension (128 bins) is much shorter than the range-FFT length (1024 bins); proportionally smaller windows avoid the training region spanning an unreasonable fraction of the axis. |
| Threshold factor `alpha` | | `Ntrain*(Pfa^(-1/Ntrain) - 1)` | Standard CA-CFAR threshold-scaling formula for a square-law (power-domain) detector under an exponential (Rayleigh-envelope-power) noise model — see `docs/architecture.md` and `docs/verification_strategy.md`. |

All CFAR processing operates in the power domain (`|X|^2`) consistently, so the same `alpha`
formula applies to both the 1D and 2D cases without a linear/power mismatch.

## 6. Simulation / noise

| Symbol | Meaning | Value | Rationale |
|---|---|---|---|
| `SNR_dB` | Default per-chirp, pre-FFT SNR at the beat-signal input (see D11) | 10 dB | Deliberately modest, not an unrealistically clean case, so CFAR and coherent-integration gain are both meaningfully exercised. |
| Coherent gain, range FFT | `10*log10(Ns) ~ 29 dB` | Reported separately from `SNR_dB`, never merged into it (D11). |
| Coherent gain, Doppler FFT | `10*log10(Nchirps) ~ 21 dB` | Same. |
| `seed` | RNG seed | 42 | Fixed and reused by every phase for reproducibility. |

## 7. Validation invariants (`functions/utils/validate_params.m`)

Checked programmatically at the top of every phase script, so a parameter change can't silently
violate an assumption another phase relies on:

1. `T_CRI > Tchirp_active` (D2).
2. `Fs >= 2 * f_beat(R_max_test_target)` for every target range used in a test scenario
   (Nyquist on the beat signal).
3. `d <= lambda/2 * 1.001` (grating-lobe-free spacing, small tolerance for float rounding).
4. `Ns = round(Fs * Tchirp_active)` matches the actual generated signal length (catches
   parameter drift between `config/` and a phase script).
5. For every test target: `abs(v) < v_max` (Doppler-ambiguity guard).
6. For every test target: `R < R_max` (range-ambiguity guard).
7. `Nfft_range >= Ns` (zero-padding, never truncation).

## 8. Toolbox requirements summary

- **Required:** base MATLAB only (no toolbox) for chirp generation, range/Doppler FFT, CA-CFAR,
  steering vectors, MUSIC eigendecomposition.
- **Recommended (not strictly required):** Signal Processing Toolbox, for the Hamming window
  used for sidelobe control in spectra/plots.
- **Optional, cross-validation only:** Phased Array System Toolbox (`phased.MUSICEstimator`,
  `phased.CFARDetector`) — never the primary implementation (D9).
- **Phase 7/7b (real dataset):** `h5info`/`h5read`, both part of base MATLAB — no additional
  toolbox needed. Real hardware timing parameters are in `config/get_radical_dataset_params.m`
  and documented in `docs/dataset_notes.md`.
