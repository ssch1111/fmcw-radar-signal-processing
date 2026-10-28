%% PHASE 5 -- ANGLE ESTIMATION (MUSIC + CONVENTIONAL BEAMFORMING)
%
% Simulates an 8-element ULA (d = lambda/2), estimates angle of arrival via MUSIC
% (primary method) and conventional (Bartlett) beamforming (for comparison),
% and demonstrates MUSIC's resolution advantage on two closely-spaced targets.
%
% Reuses generate_chirp/simulate_moving_target_echo/dechirp_mix/range_fft/add_awgn
% UNMODIFIED from Phases 1-4.

clear; clc; close all;

addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);
[tx, t] = generate_chirp(params);

R0 = 30.0; A0 = 0.5;
theta_grid_deg = linspace(-60, 60, 2401);
theta_grid = deg2rad(theta_grid_deg);

%% --- 5a: single-target angle estimation, 3 test angles ---
fprintf('=== PHASE 5a: single-target angle estimation ===\n');
% Deliberately not grid-aligned (grid step = 120/2400 = 0.05 deg) so the reported
% error reflects real angle-grid quantization, as in every other phase.
test_angles_deg = [-19.73, 0.31, 34.87];
for theta_true_deg = test_angles_deg
    theta_true = deg2rad(theta_true_deg);
    [R_hat, ~] = build_array_covariance(params, t, tx, R0, 0.0, A0, theta_true);
    P_music = music_spectrum(R_hat, 1, theta_grid, params.array.Nrx, params.array.d, params.wave.lambda);
    P_dbf = beamform_conventional(R_hat, theta_grid, params.array.Nrx, params.array.d, params.wave.lambda);
    [~, im] = max(P_music); [~, id] = max(P_dbf);
    fprintf('theta_true=%+.2f deg -> MUSIC=%+.2f deg (err %.2f), DBF=%+.2f deg (err %.2f)\n', ...
        theta_true_deg, theta_grid_deg(im), abs(theta_grid_deg(im)-theta_true_deg), ...
        theta_grid_deg(id), abs(theta_grid_deg(id)-theta_true_deg));
end

%% --- 5b: MUSIC vs DBF resolution, two closely-spaced targets ---
fprintf('\n=== PHASE 5b: resolution test (two targets, 6 deg apart) ===\n');
% Both targets need DISTINCT velocities -- see build_array_covariance.m and
% docs/engineering_decisions.md decision D7 (two stationary co-range-bin targets
% are indistinguishable to the outer-product-averaging covariance estimator).
sep_deg = 6.0; th1 = -sep_deg/2; th2 = sep_deg/2; v1 = 2.0; v2 = -2.0;
[R_hat2, ~] = build_array_covariance(params, t, tx, R0, [v1 v2], [A0 A0], deg2rad([th1 th2]));
[P_music2, eigvals2] = music_spectrum(R_hat2, 2, theta_grid, params.array.Nrx, params.array.d, params.wave.lambda);
P_dbf2 = beamform_conventional(R_hat2, theta_grid, params.array.Nrx, params.array.d, params.wave.lambda);

fprintf('Eigenvalues (descending): %s\n', mat2str(round(eigvals2,2)'));
fprintf('(2 dominant eigenvalues expected/required to confirm 2 sources are resolvable)\n');

[pk_m, loc_m] = findpeaks(P_music2, theta_grid_deg, 'SortStr', 'descend', 'NPeaks', 2);
[pk_d, loc_d] = findpeaks(P_dbf2, theta_grid_deg, 'SortStr', 'descend', 'NPeaks', 2);
fprintf('MUSIC top-2 peaks: %s deg (true: %.1f, %.1f)\n', mat2str(sort(loc_m)), th1, th2);
fprintf('DBF top-2 peaks:   %s deg (true: %.1f, %.1f)\n', mat2str(sort(loc_d)), th1, th2);
music_resolved = numel(loc_m)==2 && min(abs(sort(loc_m)-[th1 th2])) < 1.0;
fprintf('MUSIC resolves both true angles distinctly: %d\n', music_resolved);

%% --- Figure ---
theta0 = 34.87;
[R_hat0, ~] = build_array_covariance(params, t, tx, R0, 0.0, A0, deg2rad(theta0));
P_music0 = music_spectrum(R_hat0, 1, theta_grid, params.array.Nrx, params.array.d, params.wave.lambda);
P_dbf0 = beamform_conventional(R_hat0, theta_grid, params.array.Nrx, params.array.d, params.wave.lambda);

results_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
if ~exist(results_dir, 'dir'); mkdir(results_dir); end
plot_angle_spectrum(theta_grid_deg, P_music0, P_dbf0, theta0, ...
    P_music2, P_dbf2, [th1 th2], fullfile(results_dir, '05_angle_spectrum.png'));

%% Save results
save(fullfile(fileparts(mfilename('fullpath')), '..', 'results', 'phase5_results.mat'), ...
    'test_angles_deg', 'eigvals2', 'loc_m', 'loc_d', 'music_resolved', 'params');
