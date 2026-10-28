%% TEST -- Phase 2 range accuracy and resolution
addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);

R0 = 20; A0 = 0.5;
atten_fn = @(R) A0 * (R0./R).^2;

test_ranges = [20, 35, 50];
[tx, t] = generate_chirp(params);

for k = 1:numel(test_ranges)
    R = test_ranges(k);
    rx = simulate_target_echo(params, t, R, atten_fn(R));
    beat = dechirp_mix(tx, rx);
    beat_noisy = add_awgn(beat, params.sim.SNR_dB, A0^2);
    [profile, range_axis] = range_fft(beat_noisy, params);
    [~, idx] = max(abs(profile));
    bin_width = range_axis(2)-range_axis(1);
    err = abs(range_axis(idx) - R);
    assert(err <= bin_width, sprintf('Phase 2 FAIL at R=%.1f: error %.4f m > bin %.4f m', R, err, bin_width));
end

dR_theory = params.c/(2*params.wave.B);
assert(abs(dR_theory - params.derived.dR) < 1e-9, 'Phase 2 FAIL: dR mismatch with config');

fprintf('test_phase2_range_accuracy: PASS (all %d targets within 1 range bin)\n', numel(test_ranges));
