%% PHASE 2 -- RANGE PROCESSING
%
% Converts the Phase 1 beat-signal pipeline into a proper range profile (frequency
% axis -> range axis), adds AWGN at a stated SNR, and tests three target ranges to
% confirm the range axis scales correctly. Also runs an empirical range-resolution
% test with two targets separated by approximately one resolution cell.
%
% Reuses functions/signal/{generate_chirp,simulate_target_echo,dechirp_mix}.m from
% Phase 1 UNMODIFIED. Adds functions/processing/range_fft.m and functions/utils/add_awgn.m.

clear; clc; close all;

addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);

% Simplified Friis-style attenuation model (decision D10): amplitude ~ 1/R^2,
% calibrated so a target at R0 has amplitude A0.
R0 = 20; A0 = 0.5;
atten_fn = @(R) A0 * (R0./R).^2;

%% Test 1: multiple target ranges (axis-scaling test)
test_ranges = [20, 35, 50];   % [m], all < R_max ~ 60 m, spread across the unambiguous window
validate_params(params, struct('range', num2cell(test_ranges)));

[tx, t] = generate_chirp(params);
range_axis = [];
profiles_db = {};
labels = {};
measured_ranges = zeros(size(test_ranges));

for k = 1:numel(test_ranges)
    R = test_ranges(k);
    rx = simulate_target_echo(params, t, R, atten_fn(R));
    beat = dechirp_mix(tx, rx);
    beat_noisy = add_awgn(beat, params.sim.SNR_dB, A0^2);   % SNR relative to reference target A0 (D11)

    [profile, range_axis] = range_fft(beat_noisy, params);
    mag = abs(profile);
    profiles_db{k} = 20*log10(mag/max(mag) + eps); %#ok<*SAGROW>

    [~, idx] = max(mag);
    measured_ranges(k) = range_axis(idx);
    labels{k} = sprintf('R_{true} = %.1f m, R_{meas} = %.3f m', R, measured_ranges(k));
end

range_bin_width = range_axis(2) - range_axis(1);
range_errors = abs(measured_ranges - test_ranges);
range_pass = all(range_errors <= range_bin_width);

fprintf('--- PHASE 2 VERIFICATION: multi-range accuracy ---\n');
for k = 1:numel(test_ranges)
    fprintf('  R_true=%.2f m  R_meas=%.3f m  error=%.4f m (bin=%.4f m)\n', ...
        test_ranges(k), measured_ranges(k), range_errors(k), range_bin_width);
end
fprintf('Theoretical range resolution dR = c/(2B) = %.4f m\n', params.derived.dR);
fprintf('PASS (<= 1 bin, all targets): %d\n', range_pass);

%% Test 2: empirical range-resolution check (two targets ~1 dR apart)
% NOTE: the pipeline default Nfft_range=1024 (bin width ~0.117 m) has too few
% samples between two targets separated by exactly one theoretical resolution
% cell (dR ~ 0.150 m) to show a dip either way -- only 2 discrete bins fall in
% the gap. That is a sampling/visualization limitation, not evidence about
% resolvability itself, which is a property of the ANALOG spectrum (set by
% observation time / bandwidth, not by FFT length -- see docs/architecture.md
% §3 on zero-padding). A separate, much finer diagnostic FFT is used ONLY for
% this characterization to sample the same underlying continuous spectrum
% finely enough to see it properly; the pipeline's Nfft_range is unchanged
% everywhere else.
Rc = 40.0;
sep = params.derived.dR;   % separate by one theoretical resolution cell
R_pair = [Rc, Rc + sep];
validate_params(params, struct('range', num2cell(R_pair)));

rx_pair = simulate_target_echo(params, t, R_pair(1), atten_fn(R_pair(1))) + ...
          simulate_target_echo(params, t, R_pair(2), atten_fn(R_pair(2)));
beat_pair = dechirp_mix(tx, rx_pair);

Nfft_hires = 16384;
params_hires = params;
params_hires.adc.Nfft_range = Nfft_hires;   % local diagnostic override, not global
[profile_pair, range_axis_pair] = range_fft(beat_pair, params_hires);
mag_pair = abs(profile_pair);
mag_pair_db = 20*log10(mag_pair/max(mag_pair) + eps);

% Resolvability: a local minimum must exist between the two known target ranges
[~, idx1] = min(abs(range_axis_pair - R_pair(1)));
[~, idx2] = min(abs(range_axis_pair - R_pair(2)));
between = mag_pair(min(idx1,idx2):max(idx1,idx2));
resolved = numel(between) >= 3 && any(islocalmin(between));
if resolved
    dip_db = 20*log10(min(between(2:end-1)) / max(between(1), between(end)));
else
    dip_db = NaN;
end

fprintf('\n--- PHASE 2 VERIFICATION: resolution test (separation = 1 dR = %.4f m) ---\n', sep);
fprintf('Diagnostic FFT length: %d (bin width %.4f m); pipeline default Nfft_range=%d unchanged elsewhere.\n', ...
    Nfft_hires, range_axis_pair(2)-range_axis_pair(1), params.adc.Nfft_range);
fprintf('Targets at %.4f m and %.4f m: resolved as two distinguishable peaks = %d\n', R_pair(1), R_pair(2), resolved);
if resolved
    fprintf('Dip depth between peaks: %.2f dB\n', dip_db);
end

%% Figures
results_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
if ~exist(results_dir, 'dir'); mkdir(results_dir); end
plot_range_profile(range_axis, profiles_db, test_ranges, labels, ...
    fullfile(results_dir, '02_range_profile.png'));

%% Save results
save(fullfile(fileparts(mfilename('fullpath')), '..', 'results', 'phase2_results.mat'), ...
    'test_ranges', 'measured_ranges', 'range_errors', 'range_bin_width', 'range_pass', ...
    'R_pair', 'resolved', 'dip_db', 'params');
