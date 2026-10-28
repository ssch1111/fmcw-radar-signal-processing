%% TEST -- Phase 4 CFAR detection correctness
addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);

R0 = 20; A0 = 0.5;
atten_fn = @(R) A0 * (R0./R).^2;
[tx, t] = generate_chirp(params);

% 1D: all 3 targets must be detected
test_ranges = [20.0, 35.0, 50.0];
rx_sum = zeros(size(t));
for R = test_ranges
    rx_sum = rx_sum + simulate_target_echo(params, t, R, atten_fn(R));
end
beat = dechirp_mix(tx, rx_sum);
beat_noisy = add_awgn(beat, params.sim.SNR_dB, A0^2);
[profile, range_axis] = range_fft(beat_noisy, params);
power1d = abs(profile).^2;
[det1d, ~] = ca_cfar_1d(power1d, params.cfar.range.Ntrain, params.cfar.range.Nguard, params.cfar.Pfa);
bin_w = range_axis(2)-range_axis(1);
for R = test_ranges
    found = any(abs(range_axis(det1d) - R) < bin_w);
    assert(found, sprintf('Phase 4 FAIL: target at %.1f m not detected (1D)', R));
end

% 2D: all 3 targets (with windowing) must be detected
targets_rd = [15.0, -6.0; 35.0, 0.0; 50.0, 10.0];
beat_cube = zeros(params.adc.Ns, params.frame.Nchirps);
for k = 1:size(targets_rd,1)
    rx_cube = simulate_moving_target_echo(params, t, targets_rd(k,1), targets_rd(k,2), atten_fn(targets_rd(k,1)));
    beat_cube = beat_cube + dechirp_mix(tx, rx_cube);
end
beat_cube_noisy = add_awgn(beat_cube, params.sim.SNR_dB, A0^2);
beat_windowed = apply_window(beat_cube_noisy, 1, 'hamming');
[rp2, range_axis2] = range_fft(beat_windowed, params);
rp2 = apply_window(rp2, 2, 'hamming');
[rd, vaxis] = doppler_fft(rp2, params);
power2d = abs(rd).^2;
[det2d, ~] = ca_cfar_2d(power2d, params.cfar.range.Ntrain, params.cfar.range.Nguard, ...
    params.cfar.doppler.Ntrain, params.cfar.doppler.Nguard, params.cfar.Pfa);
for k = 1:size(targets_rd,1)
    [~, ri] = min(abs(range_axis2 - targets_rd(k,1)));
    [~, vi] = min(abs(vaxis - targets_rd(k,2)));
    assert(any(any(det2d(max(1,ri-1):ri+1, max(1,vi-1):vi+1))), ...
        sprintf('Phase 4 FAIL: target #%d not detected (2D)', k));
end

fprintf('test_phase4_cfar: PASS (all 1D and 2D targets detected)\n');
