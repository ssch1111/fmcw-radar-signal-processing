# Dataset Notes — Phase 7 Real-Data Validation

**Chosen dataset: RaDICaL** (official small sample subset), selected from the 5 candidates
evaluated in `docs/dataset_comparison.md`.

**Status: executed and passed.** The sample file (`indoor_sample_50.h5`) was MD5-verified as
genuine and uncorrupted, and `src/phase7_dataset_validation.m` has been run to completion in
MATLAB against the real file. Two real bugs (D21: wrong HDF5 key name plus a latent
frame-axis-order defect plus a chirps-per-frame documentation mismatch; D22: complex ADC samples
arriving as a MATLAB struct) were found from that run and fixed — see
`docs/engineering_decisions.md` for full diagnoses. All internal-consistency checks (range
resolution, max range, Doppler resolution, max velocity) matched their closed-form predictions
exactly, and the resulting Range-Doppler map/CFAR detections were interpreted honestly (a
leakage spike, a static-clutter ridge, two plausible genuine moving-target detections) rather
than overclaimed.

## Source

- **Dataset:** RaDICaL — "A Synchronized FMCW Radar, Depth, IMU and RGB Camera Data Dataset with
  Low-Level FMCW Radar Signals" (Lim, Markowitz, Do; IEEE Journal of Selected Topics in Signal
  Processing, 2021).
- **Official host / record:** Illinois Data Bank, DOI-backed record
  https://databank.illinois.edu/datasets/IDB-3289560 (full ~746 GB collection: indoor, 30 m,
  50 m, and high-resolution recording configurations).
- **SDK / project page:** https://github.com/moodoki/radical_sdk (loader code, documentation,
  and the official small sample used here).
- **Sample used:** the SDK's own official small sample, `indoor_sample_50.h5` (50 frames,
  ~400 MB, indoor recording), hosted at
  https://fireball.teckyianlim.me/file/flaming-cake/indoor_sample_50.h5 (MD5
  `b195ff422cc4c979eeb81623899050cb`, as documented in the SDK's README) — the dataset authors'
  own sample, provided so users can test without downloading the full collection.

## Licence

**CC BY 4.0** (Creative Commons Attribution 4.0 International), as stated in the RaDICaL SDK
repository and its Illinois Data Bank record. This licence:

- **Permits commercial and portfolio use**, including in a public GitHub repository, with
  attribution.
- Requires citation (see below).
- Does not require ShareAlike — derivative works may use a different licence.

Verified directly against the dataset's own primary sources (its GitHub repository and its
Illinois Data Bank record), not assumed or copied from a secondary summary.

## Commercial / portfolio-use determination

Permitted. CC BY 4.0 places no non-commercial restriction, unlike RadarScenes/CARRADA (CC
BY-NC-SA 4.0, ruled out for that reason — see `docs/dataset_comparison.md`) or nuScenes
(commercial use requires a separately negotiated paid licence). No further permission is needed
beyond attribution.

## Citation (required by the licence)

> Lim, Teck Yian; Markowitz, Spencer Abraham; Do, Minh (2021). RaDICaL: A Synchronized FMCW
> Radar, Depth, IMU and RGB Camera Data Dataset with Low-Level FMCW Radar Signals (ROS bag
> format). University of Illinois at Urbana-Champaign. Illinois Data Bank.
> https://doi.org/10.13012/B2IDB-3289560_V1

This citation is also included in `README.md`'s Dataset Information section.

## Data format and what this project actually reads

The sample's actual HDF5 datasets are `radar`, `radar_timestamp`, `rgb`, `rgb_timestamp`,
`depth`, `depth_timestamp` — there's no literal `adc` key. The SDK's own README confirms the
`radar` array IS the raw, pre-FFT ADC data (its `RadarFrame` class performs range/Doppler/angle
processing on this array). This project reads `radar` directly, so Phase 7 genuinely exercises
its own `range_fft.m`/`doppler_fft.m`/`ca_cfar_2d.m` code against real signal data rather than
re-plotting an already-processed product — see `src/phase7_dataset_validation.m` for the
explicit check that refuses to proceed if a `radar` stream isn't found.

The real per-frame array shape (50-frame sample) is `[304, 8, 32, 50]` (order as reported by
MATLAB's `h5info`, axis identity determined empirically at run time, not assumed by position —
see decision D21): 304 = samples/chirp (fast-time, matches the documented `adcSamples` exactly),
8 = antenna elements (matches the documented 2 TX x 4 RX virtual array exactly), 32 = chirps per
frame, 50 = frames. This sample's real chirps-per-frame (32) doesn't match the `numChirps` value
below (64) — see the table's note.

## Radar hardware / timing parameters used for Phase 7

Sourced from the RaDICaL SDK's own documented `radar.config_v1` example
(https://moodoki.github.io/radical_sdk/radarcfg_v1.html):

| Parameter | Value | Source field |
|---|---|---|
| Carrier frequency | 77 GHz | `start_frequency` |
| Chirp slope | 1e14 Hz/s (100 MHz/us) | `freqSlopeConst` |
| ADC sample rate | 9.499 MHz | `adcSampleRate` |
| Samples per chirp | 304 | `adcSamples` |
| Ramp (active chirp) duration | ~40 us | `rampEndTime` |
| Idle time | 58 us | `idle` |
| Chirps per frame | 64 documented; **32 actually observed in `indoor_sample_50.h5`** | `numChirps` (see note) |
| TX antennas (documented) | 2 | `numTx` |
| RX antennas (documented) | 4 (rx1-rx4) | — |
| Frame rate | ~30 fps | `fps` |

These are encoded in `config/get_radical_dataset_params.m`, a separate parameter struct from
`config/get_radar_params.m` (the synthetic Phases 1-6 configuration) — Phase 7 validates against
a different, real radar with its own fixed hardware timing, so it needs its own real parameter
set. Both structs use the same field-naming convention, which is what lets `range_fft.m`,
`doppler_fft.m`, and `ca_cfar_2d.m` be reused unmodified for Phase 7.

**Chirps-per-frame discrepancy (decision D21):** the `radar.config_v1` documentation page's
`numChirps=64` doesn't match this specific sample's real per-frame chirp count of 32, confirmed
by directly inspecting `indoor_sample_50.h5`. The `config_v1` page most likely documents a
different RaDICaL recording configuration (the dataset has several: indoor, 30 m, 50 m,
high-resolution), not specifically this 50-frame indoor sample. `src/phase7_dataset_validation.m`
uses the actually observed value (32) for all Doppler processing and derived quantities
(`v_max`, `dv`), overriding the documented-but-mismatched 64 at run time, and prints this
reconciliation explicitly rather than silently using either number.

**Not independently confirmed (flagged, not glossed over):**

- Whether the `radar` HDF5 stream's antenna axis reflects the 4 physical RX channels or an
  8-element TX-multiplexed virtual array (2 TX x 4 RX) — the real file's antenna axis size (8)
  matches the 8-element virtual-array hypothesis exactly, and `src/phase7_dataset_validation.m`
  determines this from the actual array shape at run time and prints what it finds, rather than
  assuming either answer.
- The physical receive-antenna spacing (assumed lambda/2 in `get_radical_dataset_params.m`, the
  standard TI mmWave-radar-board convention, but not confirmed against RaDICaL's specific
  antenna board layout). This affects only an angle-estimation step, not the range/Doppler/CFAR
  validation Phase 7 requires at minimum.

## Access and verification

`indoor_sample_50.h5` was downloaded from the SDK's official sample link and its MD5 checksum
verified as `b195ff422cc4c979eeb81623899050cb`, an exact match to the SDK's documented checksum
— confirmed genuine and uncorrupted before any processing. `src/phase7_dataset_validation.m`
checks three candidate locations automatically, so the file can sit at the project root or under
`data/radical/`.

Two real bugs were found while running `src/phase7_dataset_validation.m` against the real file
for the first time:

- **D21** — the code assumed a literal `adc` HDF5 key (the real key is `radar`) and assumed the
  frame index was the array's first dimension (it's actually last); axis identification was
  rewritten to match each dimension against its distinctive, independently known expected size
  rather than assuming position. Also surfaced: this sample's real chirps/frame (32) doesn't
  match the SDK's generic documentation (64) — the script now uses the observed value and prints
  an explicit reconciliation.
- **D22** — the `radar` dataset's complex I/Q samples arrive from `h5read` as a MATLAB struct
  with `r`/`i` fields (HDF5 has no native complex type), which crashed the first numeric
  operation on it; fixed by reassembling a proper `complex()` array immediately after reading.

Both fixes were validated by re-running the script, which matched the predicted axis
identification and compound-field names exactly. Full diagnoses are in
`docs/engineering_decisions.md` (decisions D21, D22). Phase 7 is labeled **PASS** — a
plausibility/internal-consistency PASS, not an exact-ground-truth PASS — see
the Phase 7 section of the README for the interpretation of the resulting detections.

## Git hygiene

`data/radical/` is excluded via `.gitignore` — the raw `.h5` file is never committed to this
repository.
