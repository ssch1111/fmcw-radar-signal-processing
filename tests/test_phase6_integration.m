%% TEST -- Phase 6 full multi-target pipeline (integration test)
addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);

Nrx = params.array.Nrx; d = params.array.d; lambda_ = params.wave.lambda;
[tx, t] = generate_chirp(params);

R0_ref = 20.0; A0 = 0.5;
atten_fn = @(R) A0 * (R0_ref ./ R).^2;

targets(1) = struct('id', 'T1', 'R', 18.0, 'v',  5.0, 'theta_deg', -25.0);
targets(2) = struct('id', 'T2', 'R', 32.0, 'v', -9.0, 'theta_deg',  10.0);
targets(3) = struct('id', 'T3', 'R', 45.0, 'v',  3.0, 'theta_deg',  40.0);
targets(4) = struct('id', 'T4', 'R', 55.0, 'v', -12.0, 'theta_deg',  -8.0);

beat_per_elem = zeros(params.adc.Ns, params.frame.Nchirps, Nrx);
for k = 1:numel(targets)
    rx_cube = simulate_moving_target_echo(params, t, targets(k).R, targets(k).v, atten_fn(targets(k).R));
    beat2d = dechirp_mix(tx, rx_cube);
    a = steering_vector(deg2rad(targets(k).theta_deg), Nrx, d, lambda_);
    for elem = 1:Nrx
        beat_per_elem(:,:,elem) = beat_per_elem(:,:,elem) + beat2d * a(elem);
    end
end
for elem = 1:Nrx
    beat_per_elem(:,:,elem) = add_awgn(beat_per_elem(:,:,elem), params.sim.SNR_dB, A0^2);
end

Nfft_half = floor(params.adc.Nfft_range/2);
rd_cube = zeros(Nfft_half, params.frame.Nchirps, Nrx);
for elem = 1:Nrx
    beat_win = apply_window(beat_per_elem(:,:,elem), 1, 'hamming');
    [rp, range_axis] = range_fft(beat_win, params);
    rp_win = apply_window(rp, 2, 'hamming');
    [rd, vaxis] = doppler_fft(rp_win, params);
    rd_cube(:,:,elem) = rd;
end

power_detect = sum(abs(rd_cube).^2, 3);
[det2d, ~] = ca_cfar_2d(power_detect, params.cfar.range.Ntrain, params.cfar.range.Nguard, ...
    params.cfar.doppler.Ntrain, params.cfar.doppler.Nguard, params.cfar.Pfa);
[det_r, det_d] = cluster_detections(det2d, power_detect, 2);

assert(numel(det_r) == numel(targets), ...
    sprintf('Phase 6 FAIL: expected %d clustered detections, got %d', numel(targets), numel(det_r)));

theta_grid_deg = linspace(-60, 60, 2401);
theta_grid = deg2rad(theta_grid_deg);
detections = struct('R_est', {}, 'v_est', {}, 'theta_est', {});
for i = 1:numel(det_r)
    r_idx = det_r(i); d_idx = det_d(i);
    snapshots = zeros(params.frame.Nchirps, Nrx);
    for elem = 1:Nrx
        [rp_raw, ~] = range_fft(beat_per_elem(:,:,elem), params);
        snapshots(:, elem) = rp_raw(r_idx, :).';
    end
    R_hat = estimate_covariance(snapshots);
    P_music = music_spectrum(R_hat, 1, theta_grid, Nrx, d, lambda_);
    [~, im] = max(P_music);
    detections(end+1) = struct('R_est', range_axis(r_idx), 'v_est', vaxis(d_idx), ...
        'theta_est', theta_grid_deg(im)); %#ok<AGROW>
end

results_table = associate_detections(detections, targets, 2.0);

% All 4 targets must be detected and associated
for k = 1:numel(results_table)
    assert(results_table(k).detected, sprintf('Phase 6 FAIL: target %s not detected/associated', results_table(k).id));
end

% Range error must be within a few range bins (dR ~ 0.15 m); generous bound accounts for
% CFAR peak-cell quantization plus the (uncompensated) Doppler-domain range-migration-free
% stop-and-hop model
dR = params.derived.dR;
dv = params.derived.dv;
for k = 1:numel(results_table)
    assert(results_table(k).R_err < 3*dR, sprintf('Phase 6 FAIL: %s range error %.3f m exceeds 3*dR (%.3f m)', ...
        results_table(k).id, results_table(k).R_err, 3*dR));
    assert(results_table(k).v_err < 3*dv, sprintf('Phase 6 FAIL: %s velocity error %.3f m/s exceeds 3*dv (%.3f m/s)', ...
        results_table(k).id, results_table(k).v_err, 3*dv));
    % Angle: correct SIGN is the critical check (decision D17 regression guard) plus
    % grid-resolution-level accuracy (grid step 0.05 deg)
    assert(sign(results_table(k).theta_est) == sign(results_table(k).theta_true) || abs(results_table(k).theta_true) < 1, ...
        sprintf('Phase 6 FAIL (D17 regression): %s angle sign flipped -- true %.2f deg, est %.2f deg', ...
        results_table(k).id, results_table(k).theta_true, results_table(k).theta_est));
    assert(results_table(k).theta_err <= 0.1, sprintf('Phase 6 FAIL: %s angle error %.3f deg exceeds grid tolerance', ...
        results_table(k).id, results_table(k).theta_err));
end

fprintf('test_phase6_integration: PASS (4/4 targets detected, associated, within tolerance; D17 sign regression guard passed)\n');
