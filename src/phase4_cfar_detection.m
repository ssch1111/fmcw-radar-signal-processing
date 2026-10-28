%% PHASE 4 -- CA-CFAR DETECTION
%
% Implements CA-CFAR (1D on a range profile, 2D on a Range-Doppler map), with
% guard/training cells and Pfa as configurable parameters (config/get_radar_params.m).
% Demonstrates and explains two known CA-CFAR limitations (clutter edges, mutual
% masking of close targets) rather than only showing the success case.
%
% Reuses generate_chirp/simulate_target_echo/simulate_moving_target_echo/dechirp_mix/
% range_fft/doppler_fft UNMODIFIED from Phases 1-3.

clear; clc; close all;

addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);

R0 = 20; A0 = 0.5;
atten_fn = @(R) A0 * (R0./R).^2;

[tx, t] = generate_chirp(params);

%% --- 4a: 1D CA-CFAR on a 3-target range profile ---
fprintf('=== PHASE 4a: 1D CA-CFAR (3 targets) ===\n');
test_ranges = [20.0, 35.0, 50.0];
rx_sum = zeros(size(t));
for R = test_ranges
    rx_sum = rx_sum + simulate_target_echo(params, t, R, atten_fn(R));
end
beat = dechirp_mix(tx, rx_sum);
beat_noisy = add_awgn(beat, params.sim.SNR_dB, A0^2);
[profile, range_axis] = range_fft(beat_noisy, params);
power1d = abs(profile).^2;
[det1d, thr1d] = ca_cfar_1d(power1d, params.cfar.range.Ntrain, params.cfar.range.Nguard, params.cfar.Pfa);
fprintf('Injected ranges: %s\n', mat2str(test_ranges));
fprintf('CFAR-flagged range bins: %s\n', mat2str(round(range_axis(det1d),3)));

%% --- 4b: clutter-edge limitation demo ---
fprintf('\n=== PHASE 4b: CA-CFAR limitation -- clutter edge ===\n');
N = 600;
clutter = [0.01*ones(1,300), 1.0*ones(1,300)];
noise_realization = clutter .* (-log(rand(1,N)));   % exponential(1) via inverse-CDF, matches power of complex Gaussian
profile_edge = noise_realization;
target_idx = 295;
profile_edge(target_idx) = profile_edge(target_idx) + 5.0;
[det_edge, thr_edge] = ca_cfar_1d(profile_edge, params.cfar.range.Ntrain, params.cfar.range.Nguard, params.cfar.Pfa);
fprintf('Target at bin %d (near clutter edge at bin 300): detected = %d\n', target_idx, det_edge(target_idx));
fprintf('Threshold at target bin: %.4f  (vs. same-floor bin far from edge, bin 150: %.4f)\n', ...
    thr_edge(target_idx), thr_edge(150));
fprintf(['Interpretation: training window at bin %d spans the clutter edge, inflating the\n' ...
         'noise estimate/threshold relative to a same-floor target far from any edge.\n'], target_idx);

%% --- 4c: mutual masking limitation demo ---
fprintf('\n=== PHASE 4c: CA-CFAR limitation -- mutual masking ===\n');
N2 = 200; floor2 = 0.05;
prof2 = floor2 * (-log(rand(1,N2)));
strong_idx = 100; weak_idx = 104;
prof2(strong_idx) = prof2(strong_idx) + 50.0;
prof2(weak_idx) = prof2(weak_idx) + 3.0;
[det_mask, thr_mask] = ca_cfar_1d(prof2, params.cfar.range.Ntrain, params.cfar.range.Nguard, params.cfar.Pfa);
prof2_iso = prof2; prof2_iso(strong_idx) = floor2*(-log(rand()));
[det_iso, thr_iso] = ca_cfar_1d(prof2_iso, params.cfar.range.Ntrain, params.cfar.range.Nguard, params.cfar.Pfa);
fprintf('Weak target (bin %d) detected WITH strong neighbor 4 bins away: %d (threshold %.3f)\n', ...
    weak_idx, det_mask(weak_idx), thr_mask(weak_idx));
fprintf('Same weak target detected WITHOUT the strong neighbor: %d (threshold %.3f)\n', ...
    det_iso(weak_idx), thr_iso(weak_idx));

%% --- 4d: 2D CA-CFAR on a multi-target RD map ---
fprintf('\n=== PHASE 4d: 2D CA-CFAR on multi-target RD map ===\n');
targets_rd = [15.0, -6.0; 35.0, 0.0; 50.0, 10.0];
beat_cube = zeros(params.adc.Ns, params.frame.Nchirps);
for k = 1:size(targets_rd,1)
    R = targets_rd(k,1); v = targets_rd(k,2);
    rx_cube = simulate_moving_target_echo(params, t, R, v, atten_fn(R));
    beat_cube = beat_cube + dechirp_mix(tx, rx_cube);
end
beat_cube_noisy = add_awgn(beat_cube, params.sim.SNR_dB, A0^2);

% Without windowing (rectangular), for comparison / to motivate D15
[rp_raw, range_axis2] = range_fft(beat_cube_noisy, params);
[rd_raw, vaxis] = doppler_fft(rp_raw, params);
power_raw = abs(rd_raw).^2;
[det_raw, ~] = ca_cfar_2d(power_raw, params.cfar.range.Ntrain, params.cfar.range.Nguard, ...
    params.cfar.doppler.Ntrain, params.cfar.doppler.Nguard, params.cfar.Pfa);
fprintf('WITHOUT windowing: %d total detections (targets: %d) -- motivates decision D15.\n', ...
    sum(det_raw(:)), size(targets_rd,1));

% Adopted pipeline: Hamming window on both FFT stages before CFAR (decision D15)
beat_windowed = apply_window(beat_cube_noisy, 1, 'hamming');
[rp2, ~] = range_fft(beat_windowed, params);
rp2 = apply_window(rp2, 2, 'hamming');
[rd, vaxis] = doppler_fft(rp2, params);
power2d = abs(rd).^2;
[det2d, thr2d] = ca_cfar_2d(power2d, params.cfar.range.Ntrain, params.cfar.range.Nguard, ...
    params.cfar.doppler.Ntrain, params.cfar.doppler.Nguard, params.cfar.Pfa);

fprintf('WITH Hamming windowing: %d total detections (targets: %d), %.1fx fewer than unwindowed.\n', ...
    sum(det2d(:)), size(targets_rd,1), sum(det_raw(:))/max(sum(det2d(:)),1));

found = false(size(targets_rd,1),1);
for k = 1:size(targets_rd,1)
    [~, ri] = min(abs(range_axis2 - targets_rd(k,1)));
    [~, vi] = min(abs(vaxis - targets_rd(k,2)));
    r_win = max(1,ri-1):min(numel(range_axis2),ri+1);
    v_win = max(1,vi-1):min(numel(vaxis),vi+1);
    found(k) = any(any(det2d(r_win, v_win)));
end
fprintf('All targets detected (within +/-1 bin): %s -> all: %d\n', mat2str(found'), all(found));

n_false = sum(det2d(:)) - size(targets_rd,1);
empirical_pfa = max(n_false,0) / (numel(power2d) - size(targets_rd,1));
fprintf('Empirical Pfa (this run, includes residual sidelobe detections): %.2e (design: %.2e)\n', ...
    empirical_pfa, params.cfar.Pfa);

%% --- 4e: Pfa-vs-threshold-factor sweep (noise-only map, larger trial count) ---
% Quantifies probability of false alarm versus threshold factor: runs CA-CFAR
% at several design Pfa values against a fresh noise-only map and compares
% empirical to design Pfa. This sweep was missing from an earlier version of
% this script (see docs/engineering_decisions.md decision D19) and is added
% here so the shipped code actually performs the analysis it reports.
fprintf('\n=== PHASE 4e: Pfa-vs-threshold-factor sweep (noise-only map) ===\n');
noise_beat = add_awgn(zeros(params.adc.Ns, params.frame.Nchirps), params.sim.SNR_dB, A0^2);
[rp_noise, ~] = range_fft(noise_beat, params);
[rd_noise, ~] = doppler_fft(rp_noise, params);
power_noise = abs(rd_noise).^2;

pfa_design_list = [1e-2, 1e-3, 1e-4, 1e-5];
pfa_empirical = zeros(size(pfa_design_list));
for i = 1:numel(pfa_design_list)
    [det_n, ~] = ca_cfar_2d(power_noise, params.cfar.range.Ntrain, params.cfar.range.Nguard, ...
        params.cfar.doppler.Ntrain, params.cfar.doppler.Nguard, pfa_design_list(i));
    pfa_empirical(i) = sum(det_n(:)) / numel(det_n);
    fprintf('  design Pfa=%.0e  ->  empirical Pfa=%.3e  (%d false alarms / %d cells)\n', ...
        pfa_design_list(i), pfa_empirical(i), sum(det_n(:)), numel(det_n));
end

%% Figure
mag_db = 20*log10(abs(rd)/max(abs(rd(:))) + eps);
thr_db = 20*log10(thr2d/max(thr2d(:)) + eps);
results_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
if ~exist(results_dir, 'dir'); mkdir(results_dir); end
plot_cfar_results(range_axis2, vaxis, mag_db, thr_db, det2d, targets_rd, ...
    fullfile(results_dir, '04_cfar_detections.png'));

%% Save results
save(fullfile(fileparts(mfilename('fullpath')), '..', 'results', 'phase4_results.mat'), ...
    'test_ranges', 'det1d', 'det_edge', 'det_mask', 'det_iso', 'targets_rd', 'found', ...
    'empirical_pfa', 'params');
