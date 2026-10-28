%% PHASE 7 -- REAL-DATA VALIDATION (RaDICaL dataset)
%
% Validates this project's OWN range-FFT / Doppler-FFT / CA-CFAR processing
% chain (Phases 2-4, reused UNMODIFIED here) against real recorded FMCW radar
% data.
%
% Dataset: RaDICaL ("RaDICaL: A Synchronized FMCW Radar, Depth, IMU and RGB
% Camera Data Dataset with Low-Level FMCW Radar Signals"), official small
% sample subset (50 frames, indoor recording). Source, licence, and access
% instructions are documented in docs/dataset_notes.md -- read that file
% before running this script. Licence: CC BY 4.0 (permits commercial/
% portfolio use with attribution; see docs/dataset_notes.md for the citation
% to include).
%
% This script does NOT fabricate a result if the data file is missing. It
% checks for the file first and prints exact instructions and exits if not
% found, rather than silently skipping or inventing numbers. See
% docs/dataset_notes.md for the current status.
%
% IMPORTANT DISTINCTION: this is REAL-DATA validation, not synthetic
% validation. There is no exact ground-truth range/velocity/
% angle to compute an "error" against (unlike Phases 1-6's synthetic
% scenarios, where the true target state is known exactly because THIS
% PROJECT generated it). Validation here instead checks:
%   (a) internal consistency -- do the range/Doppler axes, bin widths, and
%       CFAR threshold behave as theory predicts for THIS radar's real timing
%       parameters (config/get_radical_dataset_params.m)?
%   (b) physical plausibility -- does the strongest detected target fall
%       within the physically sensible range/velocity for an indoor human
%       subject recording (the scenario RaDICaL's "indoor" config targets)?
% This is explicitly weaker evidence than Phases 1-6's exact-ground-truth
% checks, and this script and its report say so rather than implying
% otherwise.

clear; clc; close all;

addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

rparams = get_radical_dataset_params();

%% --- Locate the dataset file ---
% Preferred location is data/radical/indoor_sample_50.h5 (kept out of Git via
% .gitignore, to avoid committing a large raw dataset), but this script also
% checks a couple of other places a downloaded file commonly ends up (repo
% root; bare data/), rather than forcing an exact path and failing on an
% otherwise-fine setup.
repo_root = fullfile(fileparts(mfilename('fullpath')), '..');
candidate_paths = { ...
    fullfile(repo_root, 'data', 'radical', 'indoor_sample_50.h5'), ...
    fullfile(repo_root, 'data', 'indoor_sample_50.h5'), ...
    fullfile(repo_root, 'indoor_sample_50.h5') ...
    };
data_path = '';
for k = 1:numel(candidate_paths)
    if isfile(candidate_paths{k})
        data_path = candidate_paths{k};
        break;
    end
end

if isempty(data_path)
    fprintf('======================================================================\n');
    fprintf('PHASE 7: REAL-DATA VALIDATION -- DATA FILE NOT FOUND\n');
    fprintf('======================================================================\n');
    fprintf('Checked (in order):\n');
    for k = 1:numel(candidate_paths)
        fprintf('  %s\n', candidate_paths{k});
    end
    fprintf(['\nThis script validates this project''s range/Doppler/CFAR pipeline against\n' ...
             'the RaDICaL dataset''s official small sample (50 frames, indoor recording,\n' ...
             '~400 MB, CC BY 4.0 licence). It is intentionally NOT committed to this\n' ...
             'repository (see .gitignore and docs/dataset_notes.md).\n\n' ...
             'TO RUN THIS SCRIPT:\n' ...
             '  1. Download the sample file from the official SDK repository:\n' ...
             '     https://fireball.teckyianlim.me/file/flaming-cake/indoor_sample_50.h5\n' ...
             '     (linked from https://github.com/moodoki/radical_sdk ; MD5\n' ...
             '     b195ff422cc4c979eeb81623899050cb -- verify this before use)\n' ...
             '  2. Place it at any of the paths checked above.\n' ...
             '  3. Re-run this script.\n\n' ...
             'See docs/dataset_notes.md for the full licence text, citation requirement,\n' ...
             'and source verification performed for this project.\n\n' ...
             'This script deliberately STOPS here rather than fabricating a result.\n']);
    return;
end
fprintf('Using data file: %s\n', data_path);

%% --- Inspect the HDF5 file structure ---
% Decision D21 (docs/engineering_decisions.md): this script originally looked
% for a dataset literally named 'adc', based on secondary-source phrasing
% ("adc" stream) in earlier research. Running it against the actual sample
% file found NO such key -- only radar/radar_timestamp/rgb/rgb_timestamp/depth/
% depth_timestamp. Verified against the RaDICaL SDK's own README
% (https://github.com/moodoki/radical_sdk/blob/master/README.md), which
% states plainly that the raw radar array is stored under the key 'radar' and
% is itself raw ADC data (the SDK's RadarFrame class performs the range/
% Doppler/angle processing ON this array, confirming it is pre-FFT) -- 'adc'
% was never a literal HDF5 key, just descriptive terminology. Fixed below.
info = h5info(data_path);
fprintf('HDF5 datasets found in %s:\n', data_path);
for k = 1:numel(info.Datasets)
    fprintf('  %-12s size=%s\n', info.Datasets(k).Name, mat2str(info.Datasets(k).Dataspace.Size));
end

if ~any(strcmp({info.Datasets.Name}, 'radar'))
    error('phase7:missing_radar_stream', ...
        ['Expected a ''radar'' dataset (the RaDICaL SDK''s raw, pre-FFT ADC stream -- see ' ...
         'docs/engineering_decisions.md decision D21) but did not find one. This script ' ...
         'requires the raw stream to genuinely exercise this project''s OWN range/Doppler FFT ' ...
         'code rather than re-consuming an already-processed product. Found datasets: %s'], ...
         strjoin({info.Datasets.Name}, ', '));
end

radar_info = info.Datasets(strcmp({info.Datasets.Name}, 'radar'));
radar_size = double(radar_info.Dataspace.Size);
fprintf('\n''radar'' dataset shape: %s\n', mat2str(radar_size));

%% --- Identify every axis empirically, by matching distinctive known counts ---
% (decision D21) The SDK's README describes the per-frame array as "arranged
% slow_time, antenna, fast_time" but does not fix which HDF5 axis is the frame
% index for a multi-frame file, and this project's own prior assumption
% ("frame index is the leading axis") does NOT match the actual file -- this
% sample's frame count (50) is NOT the first dimension. Rather than assume any
% position, every axis is matched against a DISTINCTIVE, independently known
% count instead:
%   - fast-time: Ns = 304 samples/chirp (documented, exact)
%   - antenna:   numTx*numRx = 2*4 = 8 virtual elements (documented, exact)
%   - frame:     50 (this specific sample's own documented frame count, exact)
%   - chirp:     whatever dimension is left over once the other three are
%                claimed -- see the reconciliation against the documented
%                Nchirps=64 immediately below, since that value came from a
%                different, more generic SDK documentation page and may not
%                describe this specific 50-frame indoor sample.
Ns_expected = rparams.adc.Ns;
Nrx_expected = rparams.array.numTx_documented * rparams.array.numRx_documented;
Nframes_expected = 50;   % this sample's own documented frame count, not a hardware constant

dims = radar_size;
[~, fast_time_dim] = min(abs(dims - Ns_expected));
remaining = setdiff(1:numel(dims), fast_time_dim);
[~, i] = min(abs(dims(remaining) - Nrx_expected));
antenna_dim = remaining(i);
remaining = setdiff(remaining, antenna_dim);
[~, i] = min(abs(dims(remaining) - Nframes_expected));
frame_dim = remaining(i);
chirp_dim = setdiff(remaining, frame_dim);

fprintf(['Identified axes by matching distinctive known sizes:\n' ...
    '  fast_time = dim %d (size %d, expected Ns=%d)\n' ...
    '  antenna   = dim %d (size %d, expected numTx*numRx=%d)\n' ...
    '  frame     = dim %d (size %d, expected %d frames)\n' ...
    '  chirp     = dim %d (size %d, leftover)\n'], ...
    fast_time_dim, dims(fast_time_dim), Ns_expected, ...
    antenna_dim, dims(antenna_dim), Nrx_expected, ...
    frame_dim, dims(frame_dim), Nframes_expected, ...
    chirp_dim, dims(chirp_dim));

Nchirps_actual = dims(chirp_dim);
if Nchirps_actual ~= rparams.frame.Nchirps
    fprintf(['NOTE (decision D21): this sample''s actual chirps/frame (%d) does not match the\n' ...
        'generic "radar.config_v1" documentation page''s numChirps=%d used in\n' ...
        'config/get_radical_dataset_params.m -- that page likely documents a different RaDICaL\n' ...
        'recording configuration, not this specific 50-frame indoor sample. Using the ACTUAL\n' ...
        'observed value (%d) for all Doppler processing and derived quantities below, not the\n' ...
        'mismatched documented one.\n'], Nchirps_actual, rparams.frame.Nchirps, Nchirps_actual);
    rparams.frame.Nchirps = Nchirps_actual;
    rparams.derived.v_max = rparams.wave.lambda / (4*rparams.wave.T_CRI);
    rparams.derived.dv    = rparams.wave.lambda / (2*rparams.frame.Nchirps*rparams.wave.T_CRI);
end

%% --- Read one frame and arrange it into this project's (Ns x Nchirps x Nrx) convention ---
frame_idx = 1;
start_idx = ones(1, numel(dims));
start_idx(frame_dim) = frame_idx;
read_count = dims;
read_count(frame_dim) = 1;
frame_cube = h5read(data_path, '/radar', start_idx, read_count);

% Decision D22 (docs/engineering_decisions.md): raw complex ADC I/Q samples
% have no native HDF5 numeric type. HDF5-writing libraries built on Python's
% h5py (which the RaDICaL SDK's own capture tooling uses) store a complex
% array as a COMPOUND type with two real-valued member fields (conventionally
% named 'r'/'i' or 'real'/'imag'). MATLAB's h5read returns such a dataset as a
% MATLAB struct, not a native complex array -- confirmed when this script
% first failed inside apply_window.m with "Invalid data type. Argument must
% be numeric, char, or logical" (a struct, not a numeric type, reaching a
% `.*` elementwise multiply). Reassemble it into a proper complex
% double array here, rather than leaving every downstream FFT/window function
% to handle a struct it was never designed for.
if isstruct(frame_cube)
    fn = fieldnames(frame_cube);
    fprintf('''radar'' data is a compound (real+imaginary) HDF5 type with fields: %s\n', strjoin(fn, ', '));
    real_field = fn(ismember(lower(fn), {'r', 'real', 're'}));
    imag_field = fn(ismember(lower(fn), {'i', 'imag', 'im'}));
    if numel(real_field) ~= 1 || numel(imag_field) ~= 1
        error('phase7:unrecognized_compound_fields', ...
            ['''radar'' dataset is a compound HDF5 type but its field names (%s) do not match ' ...
             'the expected real/imaginary naming (r/i, real/imag, re/im). Inspect the file ' ...
             'manually (e.g. h5disp) and update the field-name matching in this script.'], ...
             strjoin(fn, ', '));
    end
    frame_cube = complex(double(frame_cube.(real_field{1})), double(frame_cube.(imag_field{1})));
else
    frame_cube = double(frame_cube);
end
frame_cube = squeeze(frame_cube);   % drops the now-singleton frame dimension

% squeeze() shifts every axis after the removed one down by one position;
% recompute each axis's new index among the remaining three rather than
% assuming a fixed relabeling.
remaining_axes = setdiff(1:numel(dims), frame_dim);
fast_time_dim2 = find(remaining_axes == fast_time_dim);
antenna_dim2   = find(remaining_axes == antenna_dim);
chirp_dim2     = find(remaining_axes == chirp_dim);

beat_per_elem = permute(frame_cube, [fast_time_dim2, chirp_dim2, antenna_dim2]);
% beat_per_elem is now Ns x Nchirps x Nrx_found, matching this project's own
% (Ns x Nchirps x Nrx) convention used throughout Phases 5-6 -- no change to
% range_fft.m/doppler_fft.m/ca_cfar_2d.m/steering_vector.m/music_spectrum.m is
% needed; they are reused exactly as written for the synthetic phases.

%% --- Range + Doppler FFT (reusing Phase 2-3 functions, unmodified) ---
Nfft_half = floor(rparams.adc.Nfft_range/2);
Nrx = size(beat_per_elem, 3);
rd_cube = zeros(Nfft_half, rparams.frame.Nchirps, Nrx);
range_axis = []; vaxis = [];
for elem = 1:Nrx
    beat_win = apply_window(beat_per_elem(:,:,elem), 1, 'hamming');
    [rp, range_axis] = range_fft(beat_win, rparams);
    rp_win = apply_window(rp, 2, 'hamming');
    [rd, vaxis] = doppler_fft(rp_win, rparams);
    rd_cube(:,:,elem) = rd;
end
power_map = sum(abs(rd_cube).^2, 3);

fprintf('\n--- THEORETICAL vs. THIS RADAR''S ACTUAL TIMING (real hardware, not synthetic) ---\n');
fprintf('Range resolution dR = c/(2B) = %.4f m ; range-FFT bin width = %.4f m\n', ...
    rparams.derived.dR, range_axis(2)-range_axis(1));
fprintf('Max unambiguous range R_max = %.2f m\n', rparams.derived.R_max);
fprintf('Velocity resolution dv = %.4f m/s ; max unambiguous velocity v_max = %.4f m/s\n', ...
    rparams.derived.dv, rparams.derived.v_max);

%% --- CA-CFAR detection (reusing Phase 4's ca_cfar_2d.m, unmodified) ---
% NOTE: the guard/training-cell counts and Pfa below are this project's SYNTHETIC-
% scenario design values (config/get_radar_params.m), reused here AS-IS to test
% portability of the detector, NOT re-tuned for this real radar's actual clutter/
% noise statistics. This is an honest limitation of this validation, stated
% explicitly rather than silently re-tuning until "it looks right."
synth_params = get_radar_params();
[det2d, ~] = ca_cfar_2d(power_map, synth_params.cfar.range.Ntrain, synth_params.cfar.range.Nguard, ...
    synth_params.cfar.doppler.Ntrain, synth_params.cfar.doppler.Nguard, synth_params.cfar.Pfa);
n_det = sum(det2d(:));
fprintf('\nCA-CFAR (Pfa design = %.0e, reused synthetic-scenario guard/training cell counts): %d raw detections\n', ...
    synth_params.cfar.Pfa, n_det);

[det_r, det_d] = cluster_detections(det2d, power_map, 2);
fprintf('Clustered into %d detection group(s)\n', numel(det_r));

fprintf('\n%-6s%10s%10s\n', 'Det #', 'Range(m)', 'Vel(m/s)');
for i = 1:numel(det_r)
    fprintf('%-6d%10.3f%10.3f\n', i, range_axis(det_r(i)), vaxis(det_d(i)));
end

%% --- Real-data plausibility check (NOT a ground-truth error, see header) ---
fprintf('\n--- REAL-DATA PLAUSIBILITY CHECK (no exact ground truth available) ---\n');
fprintf(['RaDICaL''s "indoor" configuration targets a maximum useful range of roughly 14 m\n' ...
    '(per the dataset''s documented indoor/30m/50m configuration tiers -- see\n' ...
    'docs/dataset_notes.md). A detection outside that range for an indoor recording would be\n' ...
    'a red flag (leakage, DC offset, or an axis-identification error above), not a real target.\n']);
if ~isempty(det_r)
    for i = 1:numel(det_r)
        plausible = range_axis(det_r(i)) > 0.3 && range_axis(det_r(i)) < 14.0;
        fprintf('Detection %d at %.2f m: %s (0.3-14 m indoor-plausible window)\n', ...
            i, range_axis(det_r(i)), ternary(plausible, 'PLAUSIBLE', 'REQUIRES REVIEW'));
    end
else
    fprintf('No detections above the CFAR threshold in this frame.\n');
end

%% --- Figure ---
results_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
if ~exist(results_dir, 'dir'); mkdir(results_dir); end
power_db = 10*log10(power_map/max(power_map(:)) + 1e-16);
plot_dataset_validation(range_axis, vaxis, power_db, det_r, det_d, ...
    fullfile(results_dir, '07_dataset_validation.png'));
fprintf('\nFigure written to results/07_dataset_validation.png\n');

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
