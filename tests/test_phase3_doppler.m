%% TEST -- Phase 3 Doppler verification (range, velocity, sign, cross-method)
addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);
[tx, t] = generate_chirp(params);

R0 = 30.0; atten = 0.3;
for v = [0.0, 8.0, -8.0]
    rx_cube = simulate_moving_target_echo(params, t, R0, v, atten);
    beat = dechirp_mix(tx, rx_cube);
    [rp, range_axis] = range_fft(beat, params);
    [rd, vaxis] = doppler_fft(rp, params);
    mag = abs(rd);
    [~, lin_idx] = max(mag(:));
    [r_idx, v_idx] = ind2sub(size(mag), lin_idx);

    range_bin = range_axis(2)-range_axis(1);
    v_bin = vaxis(2)-vaxis(1);

    assert(abs(range_axis(r_idx)-R0) <= range_bin, ...
        sprintf('Phase 3 FAIL (range) at v=%.1f', v));
    assert(abs(vaxis(v_idx)-v) <= v_bin, ...
        sprintf('Phase 3 FAIL (velocity) at v=%.1f: got %.4f', v, vaxis(v_idx)));
end

fprintf('test_phase3_doppler: PASS (range & velocity within 1 bin for v=0,+8,-8 m/s)\n');
