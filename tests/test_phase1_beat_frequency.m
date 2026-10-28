%% TEST -- Phase 1 beat-frequency verification
% Pass criterion: |measured - theoretical| <= 1 FFT bin width (per specification).

addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'functions')));
addpath(fullfile(fileparts(mfilename('fullpath')), '..', 'config'));

params = get_radar_params();
rng(params.sim.seed);

target.range = 30.0;
target.attenuation = 0.30;
validate_params(params, struct('range', target.range));

[tx, t] = generate_chirp(params);
rx = simulate_target_echo(params, t, target.range, target.attenuation);
beat = dechirp_mix(tx, rx);

f_beat_theory = 2*target.range*params.wave.S/params.c;

Nfft = params.adc.Nfft_range;
spectrum_mag = abs(fft(beat, Nfft));
freq_axis = (0:Nfft-1)*(params.adc.Fs/Nfft);
half = 1:floor(Nfft/2);
[~, idx] = max(spectrum_mag(half));
f_beat_measured = freq_axis(idx);

bin_width = params.adc.Fs/Nfft;
error_hz = abs(f_beat_measured - f_beat_theory);

assert(error_hz <= bin_width, ...
    sprintf('Phase 1 FAIL: error %.3f kHz exceeds bin width %.3f kHz', error_hz/1e3, bin_width/1e3));

fprintf('test_phase1_beat_frequency: PASS (error = %.3f kHz, bin = %.3f kHz)\n', error_hz/1e3, bin_width/1e3);
