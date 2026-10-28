# Phase 7 — Dataset Selection

A comparison of candidate public FMCW radar datasets for Phase 7's real-data validation, and the
reasoning behind selecting RaDICaL.

**Method:** for each candidate, primary/official sources were consulted directly (project
websites, GitHub repositories, dataset-hosting pages, and the original papers). Every claim below
is either sourced (see citations) or explicitly marked **UNVERIFIED** where the primary source
was ambiguous or inaccessible.

## Candidates investigated

RadarScenes, CARRADA, RaDICaL, ColoRadar, and nuScenes (radar data), as required. No others were
substituted.

## The 14 evaluation criteria

1. FMCW compatibility (is the underlying radar an FMCW chirp radar, matching this project's
   signal model?)
2. Raw/low-level data availability (pre-FFT ADC/IQ samples, vs. only post-processing point
   clouds/detections)
3. Range/Doppler information availability
4. Multi-channel data for angle estimation (raw per-element data usable for MUSIC/beamforming)
5. Documentation quality
6. MATLAB compatibility (file formats readable by MATLAB without heavy custom tooling)
7. Data format
8. Dataset size (full dataset)
9. Ease of obtaining a manageable subset
10. Licence
11. Commercial/portfolio-use implications
12. Citation requirements
13. Redistribution permissions
14. Registration/access requirements

## Comparison table

| Criterion | RadarScenes | CARRADA | RaDICaL | ColoRadar | nuScenes (radar) |
|---|---|---|---|---|---|
| 1. FMCW compatibility | Yes — 4x automotive FMCW radars (77 GHz class) [[1]](#ref1) | Yes — TI automotive FMCW radar [[2]](#ref2) | Yes — 77 GHz FMCW, 3TX/4RX [[3]](#ref3) | Yes — TI AWR1843BOOST FMCW single-chip radar [[4]](#ref4) | Yes (sensor is FMCW) but data is post-processing only, see row 2 |
| 2. Raw/low-level data | **No** — point-cloud level only (range, azimuth, Doppler, RCS per detection); no ADC/IQ [[1]](#ref1) | **Ambiguous/UNVERIFIED** — "raw radar data" and separate Range-Angle-Doppler (RAD) tensors are both mentioned; whether the "raw" files are pre-FFT ADC or the radar's own post-FFT/post-detection RAD tensors was **not confirmed** from the pages fetched in this pass [[2]](#ref2) | **Yes** — explicitly pre-FFT: data is a 3D array `(slow_time, antenna, fast_time)`, i.e. raw per-chirp ADC samples per receive channel, not yet range- or Doppler-FFT'd [[3]](#ref3) | **Yes** — raw ADC capture via a DCA1000-EVM alongside the AWR1843BOOST [[4]](#ref4) | **No** — Continental-class point-cloud radar output only (range, azimuth, radial velocity, RCS); this is the same processing level as RadarScenes, not raw signal data [[5]](#ref5) |
| 3. Range/Doppler info | Point-level range + Doppler (radial velocity) present, but not a raw range-Doppler map to reprocess | RAD tensors directly provide Range-Doppler (and Range-Angle) maps; raw-file range/Doppler content UNVERIFIED | Full — recoverable via this project's own range-FFT/Doppler-FFT from the raw ADC cube | Full — recoverable via this project's own range-FFT/Doppler-FFT from raw ADC | Point-level range + radial velocity present, not reprocessable |
| 4. Multi-channel angle data | 4 separate radar units (different mounting angles), not a single coherent RX array for MUSIC | UNVERIFIED whether raw per-channel ADC (vs. antenna count baked into the RAD tensor) is exposed | **Yes** — explicit `antenna` axis in the raw cube, suited to MUSIC/DBF as implemented in this project's Phase 5 | Likely yes (AWR1843 has multiple RX channels) but exact per-channel raw exposure **UNVERIFIED** from the pages fetched | No — only a single fused azimuth angle per point is provided, not a raw array snapshot |
| 5. Documentation quality | Good — dedicated project site + arXiv paper + Zenodo record [[1]](#ref1) | Good — dedicated project page + paper + GitHub, but format details for "raw" data were not clearly documented on the pages checked | Good — SDK repo + Illinois Data Bank record + IEEE paper, though the SDK repo itself is marked "pre-alpha research quality" [[3]](#ref3) | Good — dedicated project site, GitHub API loader, peer-reviewed paper [[4]](#ref4) | Excellent — large, mature devkit, FAQ, tutorials [[5]](#ref5) |
| 6. MATLAB compatibility | Point-cloud data in a documented binary/HDF5-like format via the `radar_scenes` Python helper; MATLAB support not native, would need a custom reader | Files are `.npy`/tensor-based (Python-oriented); MATLAB can read `.npy` only via a third-party or hand-written loader | ROS bag format (`.bag`); MATLAB's Robotics System Toolbox can read ROS bags natively (`rosbag`/`ros2bag` functions), a genuine advantage if that toolbox is available | Custom binary format with a Python/C++ API (`azinke/coloradar`); no MATLAB reader found — would need a custom binary parser | Well-supported Python devkit; MATLAB compatibility would again require a custom reader for its binary formats |
| 7. Data format | Custom point-cloud format (HDF5-based) [[1]](#ref1) | `.npy` tensors (RAD) + raw files of unconfirmed format [[2]](#ref2) | ROS bag (`.bag`), with an HDF5 "sample" export also mentioned [[3]](#ref3) | Custom binary (radar cube / raw ADC) [[4]](#ref4) | Custom binary + `.pcd`-like radar point files, via devkit [[5]](#ref5) |
| 8. Dataset size (full) | "Over 4 hours" of driving; exact GB **UNVERIFIED** from the pages fetched, but automotive point-cloud datasets of this length are typically a few GB | 23 GB compressed (core) / ~90 GB uncompressed; RAD tensors separately 176 GB compressed / ~198 GB uncompressed [[2]](#ref2) | ~746 GB total across all capture sessions (indoor, 30 m, 50 m, high-res configurations) [[6]](#ref6) | 52 sequences, 145+ minutes; raw-ADC 3D-radar datasets of this length are typically hundreds of GB to low TB (exact figure **UNVERIFIED** from the pages fetched) | Full nuScenes ~300+ GB (all sensors); radar-only portion is much smaller but was not isolated in this pass |
| 9. Manageable subset | Likely easy — Zenodo record allows selective file download; exact per-file breakdown **UNVERIFIED** | Core 23 GB dataset is a self-contained, separately downloadable subset (independent of the 176 GB RAD tensors) [[2]](#ref2) | **Easiest of all 5** — an explicit ~400 MB / 50-frame sample dataset is hosted separately for exactly this purpose [[3]](#ref3) | No small official subset identified; would need to manually select 1-2 of the 52 sequences (individual sequence size **UNVERIFIED**) | A single scene (~20 s) can be pulled from the "mini" nuScenes split, but that split's radar content is the same point-cloud level, not raw |
| 10. Licence | CC BY-NC-SA 4.0 [[1]](#ref1) | Dataset: CC BY-NC-SA 4.0 (code: GPL-3.0) [[2]](#ref2) | **CC BY 4.0** [[3]](#ref3)[[6]](#ref6) | **Apache 2.0** [[4]](#ref4) | Free for non-commercial/research use; commercial use requires a separately negotiated paid licence from the dataset owner [[7]](#ref7) |
| 11. Commercial/portfolio-use implications | Non-commercial only — a public GitHub portfolio repo showcasing personal skill is normally fine under "NC" licences (no revenue derived from the repo itself), but the dataset **could not be used in any commercial product or paid work** | Same NC restriction as RadarScenes | **No commercial restriction** — CC BY permits commercial use with attribution, the least restrictive of all 5 for a portfolio that might later be reused commercially | **No commercial restriction** — Apache 2.0 is a permissive software-style licence with no non-commercial clause | Commercial use requires directly contacting nuScenes/Motional for a paid licence; a public portfolio repo is very likely fine under their research-use allowance, but this was not separately confirmed for portfolio-specific use |
| 12. Citation requirements | Yes, explicit citation requested [[1]](#ref1) | Yes, explicit BibTeX provided [[2]](#ref2) | Yes, DOI-based citation, standard for CC BY [[3]](#ref3) | Yes, explicit paper citation (Kramer et al., IJRR 2022) [[4]](#ref4) | Yes, two explicit citations (nuScenes paper; Panoptic nuScenes paper if using those extensions) [[8]](#ref8) |
| 13. Redistribution permissions | ShareAlike required if redistributing derivatives; no redistribution of the raw dataset itself implied as permitted beyond normal CC terms | Same ShareAlike consideration as RadarScenes | CC BY imposes no ShareAlike restriction; redistribution of derivatives is permitted with attribution | Apache 2.0 permits redistribution with attribution and licence notice | Redistribution of the raw dataset is restricted by their Terms of Use (registration-gated download; not an open redistribution licence) |
| 14. Registration/access | None mentioned — direct Zenodo download [[1]](#ref1) | None mentioned — direct download from a personal webpage, or Docker script [[2]](#ref2) | None mentioned — direct download from Illinois Data Bank (Globus transfer available) [[6]](#ref6) | None mentioned — direct download from the project's own portal [[4]](#ref4) | **Registration required** — must create an account and accept Terms of Use before downloading [[5]](#ref5) |

## Recommendation

Given this project's specific validation goal — running the *actual implemented* range-FFT,
Doppler-FFT, CFAR, and (where possible) MUSIC angle-estimation code from Phases 2-5 against
*real* signal data, not against someone else's already-processed point clouds — the raw/
multi-channel ADC availability (criteria 2 and 4) is the dominant, non-negotiable filter.
That immediately rules out **RadarScenes** and **nuScenes** for anything beyond a
range/Doppler *point-level* sanity check: both provide post-processing point clouds, not
signals this project's own FFT/CFAR code can be run on.

That leaves **CARRADA**, **RaDICaL**, and **ColoRadar** as the real candidates, distinguished as
requested:

- **Technically best fit for this project's pipeline:** **RaDICaL**. Its raw data is
  explicitly a `(slow_time, antenna, fast_time)` cube — i.e. exactly the per-chirp,
  per-element ADC samples this project's `range_fft.m` → `doppler_fft.m` → `ca_cfar_2d.m` →
  `music_spectrum.m` chain is built to consume, at a 77 GHz FMCW carrier consistent with this
  project's own chosen parameters (decision: automotive/mmWave band). CARRADA and ColoRadar are
  both plausible but their raw-file format for genuine pre-FFT signal access is **UNVERIFIED**
  from official documentation alone (CARRADA appears oriented around already-computed RAD
  tensors; ColoRadar's raw-ADC path exists per its hardware description but was not confirmed
  file-format-by-file-format in this pass).

- **Easiest to obtain and work with:** **RaDICaL**, by a clear margin — it is the only one of
  the 5 with an official, separately-hosted small sample (~400 MB, 50 frames) built for exactly
  this "manageable subset" use case, avoiding a multi-hundred-GB download entirely.

- **Best for demonstrating actual signal processing (not just consuming someone else's
  processed output):** **RaDICaL**, for the same reason as "technically best fit" — raw ADC
  input is what lets this project's own FFT/CFAR/MUSIC code do real work, rather than only
  re-plotting a vendor's already-computed detections.

- **Safest from a licensing/portfolio perspective:** **RaDICaL** (CC BY 4.0) and **ColoRadar**
  (Apache 2.0) are tied here — both are unambiguously commercial-use-permitting, attribution-only
  licences with no negotiation required, unlike CARRADA/RadarScenes (CC BY-NC-SA, no commercial
  use at all) or nuScenes (commercial use requires a separate paid agreement).

**Overall recommendation: RaDICaL**, using its official small sample subset (~400 MB / 50
frames) rather than the full ~746 GB collection. It is simultaneously the technically best fit,
the easiest to obtain, the best demonstration of this project's own signal-processing code
(not a vendor's pre-processed output), and tied for the safest licence. The main residual risk,
flagged honestly rather than glossed over: the RaDICaL SDK repository describes itself as
"pre-alpha research quality," so some custom reader work should be expected, and the exact
receive-antenna geometry (element spacing, array layout) needed for a MUSIC/DBF angle-estimation
demonstration was **not confirmed** in this pass and would need to be extracted from the
dataset's own metadata/config files before Phase 7 angle-estimation validation could be
attempted — range/Doppler/CFAR validation (the "at minimum" requirement) does not depend on that
detail and could proceed regardless.

## Sources

<a id="ref1"></a>[1] RadarScenes project site, https://radar-scenes.com/ ; RadarScenes paper,
https://arxiv.org/abs/2104.02493 ; Zenodo record, https://zenodo.org/records/4559821

<a id="ref2"></a>[2] CARRADA project page, https://arthurouaknine.github.io/codeanddata/carrada ;
CARRADA GitHub, https://github.com/valeoai/carrada_dataset

<a id="ref3"></a>[3] RaDICaL SDK GitHub, https://github.com/moodoki/radical_sdk

<a id="ref4"></a>[4] ColoRadar project site, https://arpg.github.io/coloradar/ ; ColoRadar
GitHub loader, https://github.com/azinke/coloradar ; ColoRadar paper (IJRR 2022),
https://dx.doi.org/10.1177/02783649211068535

<a id="ref5"></a>[5] nuScenes devkit GitHub, https://github.com/nutonomy/nuscenes-devkit

<a id="ref6"></a>[6] RaDICaL dataset record, Illinois Data Bank,
https://databank.illinois.edu/datasets/IDB-3289560

<a id="ref7"></a>[7] nuScenes devkit FAQ (licensing/commercial-use terms),
https://github.com/nutonomy/nuscenes-devkit/blob/master/docs/faqs.md ; full terms at
https://www.nuscenes.org/terms-of-use (page requires JavaScript; not independently rendered in
this pass — FAQ citation above is the primary evidence used)

<a id="ref8"></a>[8] nuScenes citation requirements, per the devkit README/FAQ (arXiv:1903.11027
for nuScenes/nuImages; arXiv:2109.03805 for Panoptic nuScenes / nuScenes-lidarseg)
