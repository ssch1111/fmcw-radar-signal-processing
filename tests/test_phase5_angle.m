%% TEST -- Phase 5 angle estimation
addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);
[tx, t] = generate_chirp(params);

R0 = 30.0; A0 = 0.5;
theta_grid_deg = linspace(-60, 60, 2401);
theta_grid = deg2rad(theta_grid_deg);
grid_step = theta_grid_deg(2) - theta_grid_deg(1);

for theta_true_deg = [-19.73, 0.31, 34.87]
    theta_true = deg2rad(theta_true_deg);
    [R_hat, ~] = build_array_covariance(params, t, tx, R0, 0.0, A0, theta_true);
    P_music = music_spectrum(R_hat, 1, theta_grid, params.array.Nrx, params.array.d, params.wave.lambda);
    [~, im] = max(P_music);
    err = abs(theta_grid_deg(im) - theta_true_deg);
    assert(err <= grid_step, sprintf('Phase 5 FAIL: MUSIC angle error %.3f deg > grid step %.3f deg', err, grid_step));
end

% Resolution test: MUSIC must show 2 dominant eigenvalues and resolve both peaks
sep_deg = 6.0; th1 = -sep_deg/2; th2 = sep_deg/2;
[R_hat2, ~] = build_array_covariance(params, t, tx, R0, [2.0 -2.0], [A0 A0], deg2rad([th1 th2]));
[P_music2, eigvals2] = music_spectrum(R_hat2, 2, theta_grid, params.array.Nrx, params.array.d, params.wave.lambda);
assert(eigvals2(2) > 10*eigvals2(3), 'Phase 5 FAIL: second eigenvalue not clearly above the noise floor (sources not decorrelated)');
[pk, loc] = findpeaks(P_music2, theta_grid_deg, 'SortStr', 'descend', 'NPeaks', 2);
assert(numel(loc) == 2, 'Phase 5 FAIL: MUSIC did not produce 2 distinct peaks');
assert(min(abs(sort(loc) - [th1 th2])) < 1.0, 'Phase 5 FAIL: MUSIC peaks do not match true angles');

fprintf('test_phase5_angle: PASS (3 single-target angles + 2-target MUSIC resolution)\n');
