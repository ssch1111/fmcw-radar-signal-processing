%% PHASE 6 -- FULL MULTI-TARGET PIPELINE
%
% Integrates every prior phase into one pipeline:
%   FMCW array chirp cube -> per-element range FFT -> per-element Doppler FFT
%   -> non-coherent Range-Doppler power map -> 2D CA-CFAR -> cluster adjacent
%   detections -> per-detection MUSIC angle estimate -> associate to ground
%   truth (validation only) -> annotated summary figure + table.
%
% Reuses, UNMODIFIED except for the decision-D17 covariance-formula fix (see
% functions/angle/estimate_covariance.m and docs/engineering_decisions.md D17):
%   generate_chirp, simulate_moving_target_echo, dechirp_mix (Phase 1/3)
%   range_fft, doppler_fft, add_awgn, apply_window (Phase 2-4)
%   ca_cfar_2d (Phase 4)
%   steering_vector, music_spectrum, estimate_covariance (Phase 5, D17-fixed)
% New in this phase: cluster_detections.m, associate_detections.m,
% plot_full_scenario.m.

clear; clc; close all;

addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);

Nrx = params.array.Nrx;
d   = params.array.d;
lambda_ = params.wave.lambda;

[tx, t] = generate_chirp(params);

R0_ref = 20.0;
A0 = 0.5;
atten_fn = @(R) A0 * (R0_ref ./ R).^2;

%% --- Scenario: 4 targets, distinct range/velocity/angle, each in its own range bin ---
targets(1) = struct('id', 'T1', 'R', 18.0, 'v',  5.0, 'theta_deg', -25.0);
targets(2) = struct('id', 'T2', 'R', 32.0, 'v', -9.0, 'theta_deg',  10.0);
targets(3) = struct('id', 'T3', 'R', 45.0, 'v',  3.0, 'theta_deg',  40.0);
targets(4) = struct('id', 'T4', 'R', 55.0, 'v', -12.0, 'theta_deg',  -8.0);

fprintf('======================================================================\n');
fprintf('PHASE 6: Full multi-target pipeline\n');
fprintf('======================================================================\n');
for k = 1:numel(targets)
    assert(targets(k).R < params.derived.R_max, 'Target %s range exceeds R_max', targets(k).id);
    assert(abs(targets(k).v) < params.derived.v_max, 'Target %s velocity exceeds v_max', targets(k).id);
end

%% --- Build the per-element beat cube (Ns x Nchirps x Nrx) ---
beat_per_elem = zeros(params.adc.Ns, params.frame.Nchirps, Nrx);
for k = 1:numel(targets)
    rx_cube = simulate_moving_target_echo(params, t, targets(k).R, targets(k).v, atten_fn(targets(k).R));
    beat2d = dechirp_mix(tx, rx_cube);                                    % Ns x Nchirps
    a = steering_vector(deg2rad(targets(k).theta_deg), Nrx, d, lambda_);  % Nrx x 1
    for elem = 1:Nrx
        beat_per_elem(:,:,elem) = beat_per_elem(:,:,elem) + beat2d * a(elem);
    end
end
for elem = 1:Nrx
    beat_per_elem(:,:,elem) = add_awgn(beat_per_elem(:,:,elem), params.sim.SNR_dB, A0^2);
end

%% --- Windowed range+Doppler FFT per element (decision D15) ---
Nfft_half = floor(params.adc.Nfft_range/2);
rd_cube = zeros(Nfft_half, params.frame.Nchirps, Nrx);
range_axis = [];
vaxis = [];
for elem = 1:Nrx
    beat_win = apply_window(beat_per_elem(:,:,elem), 1, 'hamming');
    [rp, range_axis] = range_fft(beat_win, params);
    rp_win = apply_window(rp, 2, 'hamming');
    [rd, vaxis] = doppler_fft(rp_win, params);
    rd_cube(:,:,elem) = rd;
end

% Detection map: non-coherent sum of power across elements (boosts SNR for detection)
power_detect = sum(abs(rd_cube).^2, 3);
[det2d, ~] = ca_cfar_2d(power_detect, params.cfar.range.Ntrain, params.cfar.range.Nguard, ...
    params.cfar.doppler.Ntrain, params.cfar.doppler.Nguard, params.cfar.Pfa);
fprintf('Total CFAR detections (raw cells): %d\n', sum(det2d(:)));

%% --- Cluster adjacent detected cells into one detection per target ---
[det_r, det_d] = cluster_detections(det2d, power_detect, 2);
fprintf('Clustered into %d detection group(s)\n', numel(det_r));

%% --- Per-detection MUSIC angle estimate ---
theta_grid_deg = linspace(-60, 60, 2401);
theta_grid = deg2rad(theta_grid_deg);

detections = struct('R_est', {}, 'v_est', {}, 'theta_est', {});
for i = 1:numel(det_r)
    r_idx = det_r(i);
    d_idx = det_d(i);
    R_est = range_axis(r_idx);
    v_est = vaxis(d_idx);

    % Per-detection MUSIC: build the covariance from ALL chirps at this range bin
    % (decision D7), using the UNWINDOWED range FFT so the raw per-chirp phase
    % progression used for the covariance is not perturbed by the detection-stage
    % window.
    snapshots = zeros(params.frame.Nchirps, Nrx);
    for elem = 1:Nrx
        [rp_raw, ~] = range_fft(beat_per_elem(:,:,elem), params);
        snapshots(:, elem) = rp_raw(r_idx, :).';
    end
    R_hat = estimate_covariance(snapshots);                          % decision D17
    P_music = music_spectrum(R_hat, 1, theta_grid, Nrx, d, lambda_);
    [~, im] = max(P_music);

    detections(end+1) = struct('R_est', R_est, 'v_est', v_est, 'theta_est', theta_grid_deg(im)); %#ok<AGROW>
end

%% --- Associate detections to ground truth (validation only) ---
results_table = associate_detections(detections, targets, 2.0);

fprintf('\n%-6s%8s%10s%8s%8s%10s%8s%9s%9s%8s\n', 'Target','True R','Est R','R err','True V','Est V','V err','True th','Est th','th err');
for k = 1:numel(results_table)
    r = results_table(k);
    if r.detected
        fprintf('%-6s%8.2f%10.3f%8.3f%8.2f%10.3f%8.3f%9.2f%9.2f%8.2f\n', ...
            r.id, r.R_true, r.R_est, r.R_err, r.v_true, r.v_est, r.v_err, r.theta_true, r.theta_est, r.theta_err);
    else
        fprintf('%-6s%8.2f  MISSED DETECTION\n', r.id, r.R_true);
    end
end

detected_mask = arrayfun(@(r) r.detected, results_table);
mean_R_err = mean(arrayfun(@(r) r.R_err, results_table(detected_mask)));
mean_v_err = mean(arrayfun(@(r) r.v_err, results_table(detected_mask)));
mean_th_err = mean(arrayfun(@(r) r.theta_err, results_table(detected_mask)));
fprintf('\nDetections: %d/%d\n', sum(detected_mask), numel(targets));
fprintf('Mean range error: %.4f m | Mean velocity error: %.4f m/s | Mean angle error: %.4f deg\n', ...
    mean_R_err, mean_v_err, mean_th_err);

%% --- Figure ---
power_norm = power_detect / max(power_detect(:));
power_db = 10*log10(power_norm + 1e-16);   % power_detect is already |X|^2 summed across elements

results_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
if ~exist(results_dir, 'dir'); mkdir(results_dir); end
plot_full_scenario(range_axis, vaxis, power_db, targets, results_table, ...
    fullfile(results_dir, '06_full_scenario_summary.png'), mean_R_err, mean_v_err, mean_th_err);
fprintf('\nFigure written to results/06_full_scenario_summary.png\n');

%% --- Save results ---
mat_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
if ~exist(mat_dir, 'dir'); mkdir(mat_dir); end
save(fullfile(mat_dir, 'phase6_results.mat'), ...
    'targets', 'results_table', 'mean_R_err', 'mean_v_err', 'mean_th_err', 'params');
