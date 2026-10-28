%% PHASE 3 -- RANGE-DOPPLER MAP
%
% Builds a chirp train (Nchirps=128) for a moving point target, applies range FFT
% per chirp (fast time) then Doppler FFT across chirps (slow time), and verifies
% range/velocity/resolution/v_max against theory for a stationary target and both
% velocity directions.
%
% Reuses generate_chirp.m, simulate_target_echo.m, dechirp_mix.m, range_fft.m
% UNMODIFIED from Phases 1-2, with one exception: simulate_target_echo.m was
% corrected DURING this phase to include the carrier round-trip phase term (see
% docs/engineering_decisions.md) -- this fix does not change Phase 1/2 results (verified
% by re-running their tests) but was necessary for any Doppler information to be
% present at all.

clear; clc; close all;

addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);

[tx, t] = generate_chirp(params);

%% --- Cross-method self-consistency check (decision D6) ---
R0_test = 30.0; v_test = 8.0; atten_test = 0.3;

rx_cube_A = simulate_moving_target_echo(params, t, R0_test, v_test, atten_test);
beat_A = dechirp_mix(tx, rx_cube_A);

tau0 = 2*R0_test/params.c;
rx0 = simulate_target_echo(params, t, R0_test, atten_test);
beat0 = dechirp_mix(tx, rx0);                      % 1 x Ns static beat signal at R0
fd = 2*v_test/params.wave.lambda;
m = 0:params.frame.Nchirps-1;
doppler_phasor = exp(1j*2*pi*fd*m*params.wave.T_CRI);
beat_B = beat0.' * doppler_phasor;                 % Ns x Nchirps via outer product

[rp_A, ~] = range_fft(beat_A, params);
[rp_B, ~] = range_fft(beat_B, params);
[rd_A, ~] = doppler_fft(rp_A, params);
[rd_B, ~] = doppler_fft(rp_B, params);
[~, peakA] = max(abs(rd_A(:)));
[~, peakB] = max(abs(rd_B(:)));
cross_check_agree = (peakA == peakB);

fprintf('--- PHASE 3 CROSS-METHOD SELF-CONSISTENCY CHECK (decision D6) ---\n');
fprintf('Method A (stop-and-hop) / Method B (Doppler phasor) peak bins match: %d\n', cross_check_agree);

%% --- Main verification: stationary, +v, -v ---
cases = struct('label', {'stationary','positive_velocity','negative_velocity'}, ...
               'v', {0.0, 8.0, -8.0});
R0 = 30.0; atten = 0.3;
results = struct();

for i = 1:numel(cases)
    v = cases(i).v;
    rx_cube = simulate_moving_target_echo(params, t, R0, v, atten);
    beat = dechirp_mix(tx, rx_cube);
    [rp, range_axis] = range_fft(beat, params);
    [rd, vaxis] = doppler_fft(rp, params);
    mag = abs(rd);
    [~, lin_idx] = max(mag(:));
    [r_idx, v_idx] = ind2sub(size(mag), lin_idx);

    R_meas = range_axis(r_idx);
    v_meas = vaxis(v_idx);

    results.(cases(i).label).R_meas = R_meas;
    results.(cases(i).label).v_meas = v_meas;
    results.(cases(i).label).rd = rd;
    results.(cases(i).label).range_axis = range_axis;
    results.(cases(i).label).vaxis = vaxis;

    range_bin = range_axis(2)-range_axis(1);
    v_bin = vaxis(2)-vaxis(1);
    fprintf('\n[%s] v_true=%+.2f m/s  R0=%.2f m\n', cases(i).label, v, R0);
    fprintf('  R_meas=%.4f m (error %.4f m, bin %.4f m)\n', R_meas, abs(R_meas-R0), range_bin);
    fprintf('  v_meas=%.4f m/s (error %.4f m/s, bin %.4f m/s)\n', v_meas, abs(v_meas-v), v_bin);
end

fprintf('\nTheoretical v_max = %.4f m/s, dv = %.4f m/s\n', params.derived.v_max, params.derived.dv);

%% Figure (positive-velocity case)
r = results.positive_velocity;
mag_db = 20*log10(abs(r.rd)/max(abs(r.rd(:))) + eps);
gt.range = R0; gt.velocity = 8.0;

results_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'results');
if ~exist(results_dir, 'dir'); mkdir(results_dir); end
plot_range_doppler_map(r.range_axis, r.vaxis, mag_db, gt, ...
    fullfile(results_dir, '03_range_doppler_map.png'));

%% Save results
save(fullfile(fileparts(mfilename('fullpath')), '..', 'results', 'phase3_results.mat'), ...
    'results', 'cross_check_agree', 'params');
